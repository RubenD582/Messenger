// debug.js - Debug and monitoring endpoints
const express = require("express");
const router = express.Router();
const { authenticateToken } = require("../middleware/authMiddleware");
const db = require("../db");
const redis = require('../config/redisClient');
const reliabilityService = require('../services/messageReliabilityService');

// GET /debug/health - Overall system health check
router.get("/health", async (req, res) => {
  try {
    // Check Redis
    let redisStatus = 'unknown';
    try {
      await redis.ping();
      redisStatus = 'healthy';
    } catch (e) {
      redisStatus = 'unhealthy';
    }

    // Check PostgreSQL
    let pgStatus = 'unknown';
    try {
      await db.query('SELECT 1');
      pgStatus = 'healthy';
    } catch (e) {
      pgStatus = 'unhealthy';
    }

    // Get reliability metrics
    const metrics = await reliabilityService.getMetrics();

    res.json({
      status: (redisStatus === 'healthy' && pgStatus === 'healthy') ? 'healthy' : 'degraded',
      timestamp: new Date().toISOString(),
      services: {
        redis: redisStatus,
        postgresql: pgStatus,
        kafka: 'check logs', // Can't easily check without additional tracking
      },
      reliability: metrics,
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message,
    });
  }
});

// GET /debug/conversation/:conversationId - Debug a specific conversation
router.get("/conversation/:conversationId", authenticateToken, async (req, res) => {
  const { conversationId } = req.params;
  const userId = req.user.userId;

  try {
    // Verify user is part of conversation
    const [user1, user2] = conversationId.split('_');
    if (userId !== user1 && userId !== user2) {
      return res.status(403).json({ message: "Unauthorized" });
    }

    // Get all messages from PostgreSQL
    const pgMessages = await db.query(`
      SELECT
        message_id,
        sender_id,
        receiver_id,
        message,
        sequence_id,
        timestamp,
        message_type,
        read_at,
        delivered_at,
        deleted_at,
        conversation_id
      FROM chats
      WHERE conversation_id = $1
      ORDER BY sequence_id ASC
    `, [conversationId]);

    // Get Redis user sockets
    const user1Socket = await redis.get(`user_socket:${user1}`);
    const user2Socket = await redis.get(`user_socket:${user2}`);

    // Get offline message queues
    const user1OfflineMessages = await redis.lrange(`offline_messages:${user1}`, 0, -1);
    const user2OfflineMessages = await redis.lrange(`offline_messages:${user2}`, 0, -1);

    // Get sequence counter
    const sequenceCounter = await redis.get(`conversation_seq:${conversationId}`);

    res.json({
      conversationId,
      statistics: {
        totalMessages: pgMessages.rows.length,
        deletedMessages: pgMessages.rows.filter(m => m.deleted_at !== null).length,
        unreadMessages: pgMessages.rows.filter(m => m.read_at === null).length,
        currentSequenceId: sequenceCounter || 0,
      },
      users: {
        user1: {
          userId: user1,
          socketId: user1Socket || null,
          isOnline: !!user1Socket,
          queuedMessages: user1OfflineMessages.length,
        },
        user2: {
          userId: user2,
          socketId: user2Socket || null,
          isOnline: !!user2Socket,
          queuedMessages: user2OfflineMessages.length,
        },
      },
      messages: pgMessages.rows,
      queuedMessages: {
        user1: user1OfflineMessages.map(m => JSON.parse(m)),
        user2: user2OfflineMessages.map(m => JSON.parse(m)),
      },
    });

  } catch (error) {
    console.error("Error debugging conversation:", error);
    res.status(500).json({
      message: "Debug failed",
      error: error.message,
    });
  }
});

// GET /debug/user/:userId - Debug user's connections and state
router.get("/user/:userId", authenticateToken, async (req, res) => {
  const { userId } = req.params;
  const requesterId = req.user.userId;

  // Only allow users to debug themselves (security)
  if (userId !== requesterId) {
    return res.status(403).json({ message: "Can only debug your own user" });
  }

  try {
    // Get user's socket connection
    const socketId = await redis.get(`user_socket:${userId}`);

    // Get user's conversations
    const conversations = await db.query(`
      SELECT DISTINCT conversation_id
      FROM chats
      WHERE (sender_id = $1 OR receiver_id = $1)
      AND deleted_at IS NULL
    `, [userId]);

    // Get offline message queue
    const offlineMessages = await redis.lrange(`offline_messages:${userId}`, 0, -1);

    // Get unread count cache
    const unreadCountCache = await redis.get(`unread_count:${userId}`);

    res.json({
      userId,
      connection: {
        socketId: socketId || null,
        isConnected: !!socketId,
      },
      conversations: conversations.rows.map(c => c.conversation_id),
      queuedMessages: offlineMessages.length,
      queuedMessagesDetails: offlineMessages.map(m => JSON.parse(m)),
      cache: {
        unreadCount: unreadCountCache ? parseInt(unreadCountCache) : null,
      },
    });

  } catch (error) {
    console.error("Error debugging user:", error);
    res.status(500).json({
      message: "Debug failed",
      error: error.message,
    });
  }
});

// POST /debug/send-test-message - Send a test message to verify the pipeline
router.post("/send-test-message", authenticateToken, async (req, res) => {
  const { receiverId } = req.body;
  const senderId = req.user.userId;

  if (!receiverId) {
    return res.status(400).json({ message: "receiverId required" });
  }

  try {
    const { producer } = require('../kafkaClient');
    const { v4: uuidv4 } = require('uuid');

    // Generate conversation ID
    const conversationId = [senderId, receiverId].sort().join('_');

    // Get next sequence ID
    const sequenceId = await redis.incr(`conversation_seq:${conversationId}`);

    const testMessage = {
      messageId: uuidv4(),
      conversationId,
      senderId,
      receiverId,
      message: `[TEST] Message sent at ${new Date().toISOString()}`,
      messageType: 'text',
      sequenceId,
      timestamp: new Date().toISOString(),
      metadata: {},
    };

    console.log(`🧪 TEST: Publishing test message to Kafka`);
    console.log(`   Message ID: ${testMessage.messageId}`);
    console.log(`   Conversation: ${conversationId}`);
    console.log(`   Sequence: ${sequenceId}`);

    // Publish to Kafka
    await producer.send({
      topic: 'chat-messages',
      messages: [{
        key: conversationId,
        value: JSON.stringify(testMessage)
      }]
    });

    console.log(`✅ TEST: Message published to Kafka successfully`);

    res.json({
      success: true,
      message: "Test message sent to Kafka pipeline",
      messageDetails: testMessage,
      nextSteps: [
        "1. Check Kafka consumer logs",
        "2. Verify message saved to PostgreSQL",
        "3. Check WebSocket emission",
        "4. Verify receiver got the message",
      ],
    });

  } catch (error) {
    console.error("❌ TEST: Error sending test message:", error);
    res.status(500).json({
      message: "Test message failed",
      error: error.message,
      stack: error.stack,
    });
  }
});

// GET /debug/kafka-status - Check Kafka consumer status
router.get("/kafka-status", authenticateToken, async (req, res) => {
  try {
    const { messageConsumer, typingConsumer, receiptConsumer, producer } = require('../kafkaClient');

    res.json({
      consumers: {
        messages: {
          groupId: 'message-delivery-group',
          topic: 'chat-messages',
          // Note: Can't easily get consumer state without additional tracking
          status: 'unknown (check server logs)',
        },
        typing: {
          groupId: 'typing-broadcast-group',
          topic: 'typing-indicators',
          status: 'unknown (check server logs)',
        },
        receipts: {
          groupId: 'receipt-update-group',
          topic: 'read-receipts',
          status: 'unknown (check server logs)',
        },
      },
      producer: {
        status: 'connected',
      },
      recommendation: "Check server logs for detailed Kafka consumer status",
    });

  } catch (error) {
    res.status(500).json({
      message: "Failed to get Kafka status",
      error: error.message,
    });
  }
});

// GET /debug/reliability/metrics - Get message delivery metrics
router.get("/reliability/metrics", authenticateToken, async (req, res) => {
  try {
    const metrics = await reliabilityService.getMetrics();
    res.json({
      success: true,
      metrics,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to get reliability metrics",
      error: error.message,
    });
  }
});

// GET /debug/reliability/message/:messageId - Get delivery status for a message
router.get("/reliability/message/:messageId", authenticateToken, async (req, res) => {
  const { messageId } = req.params;

  try {
    const status = await reliabilityService.getDeliveryStatus(messageId);

    if (!status) {
      return res.status(404).json({
        message: "Message not found or delivery tracking expired",
      });
    }

    res.json({
      success: true,
      deliveryStatus: status,
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to get message delivery status",
      error: error.message,
    });
  }
});

// GET /debug/reliability/dlq - View dead letter queue
router.get("/reliability/dlq", authenticateToken, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const result = await reliabilityService.processDLQ(limit);

    res.json({
      success: true,
      dlq: result,
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to get DLQ entries",
      error: error.message,
    });
  }
});

// POST /debug/reliability/retry/:messageId - Manually retry a failed message
router.post("/reliability/retry/:messageId", authenticateToken, async (req, res) => {
  const { messageId } = req.params;

  try {
    const result = await reliabilityService.retryMessage(messageId);

    if (!result) {
      return res.status(404).json({
        message: "Message not found or max retries exceeded",
      });
    }

    res.json({
      success: true,
      message: "Retry scheduled",
      retryInfo: result,
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to retry message",
      error: error.message,
    });
  }
});

module.exports = router;
