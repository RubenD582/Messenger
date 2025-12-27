//messages.js
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const { producer } = require('../kafkaClient');
const { v4: uuidv4 } = require('uuid');

// Use shared Redis client with Sentinel support
const redis = require('../config/redisClient');

// Helper: Generate conversation ID (deterministic)
function getConversationId(userId1, userId2) {
  const sorted = [userId1, userId2].sort();
  return `${sorted[0]}_${sorted[1]}`;
}

// POST /messages/send - Send a message
router.post("/send", authenticateToken, async (req, res) => {
  const { receiverId, message, messageType = 'text', metadata = {} } = req.body;
  const senderId = req.user.userId;

  if (!receiverId || !message) {
    return res.status(400).json({ message: "Receiver ID and message are required" });
  }

  try {
    const conversationId = getConversationId(senderId, receiverId);
    const messageId = uuidv4();

    // Get next sequence ID from Redis (atomic increment)
    const sequenceId = await redis.incr(`conversation_seq:${conversationId}`);

    const messageData = {
      messageId,
      conversationId,
      senderId,
      receiverId,
      message,
      messageType,
      sequenceId,
      timestamp: new Date().toISOString(),
      metadata
    };

    // Publish to Kafka
    await producer.send({
      topic: 'chat-messages',
      messages: [{
        key: conversationId, // Partition by conversation for ordering
        value: JSON.stringify(messageData)
      }]
    });

    // Return immediately (async processing)
    res.status(202).json({
      messageId,
      sequenceId,
      status: 'queued'
    });

  } catch (error) {
    console.error("Error sending message:", error);
    res.status(500).json({ message: "Failed to send message" });
  }
});

// GET /messages/history/:conversationId - Fetch message history with pagination
router.get("/history/:conversationId", authenticateToken, async (req, res) => {
  const { conversationId } = req.params;
  const userId = req.user.userId;
  const { beforeSequence, limit = 50 } = req.query;

  try {
    // Verify user is part of conversation
    const [user1, user2] = conversationId.split('_');
    if (userId !== user1 && userId !== user2) {
      return res.status(403).json({ message: "Unauthorized" });
    }

    // Fetch from DB with pagination
    let query = `
      SELECT
        message_id,
        sender_id,
        receiver_id,
        message,
        sequence_id,
        timestamp,
        message_type,
        metadata,
        read_at,
        delivered_at,
        conversation_id
      FROM chats
      WHERE conversation_id = $1
      AND deleted_at IS NULL
    `;
    let params = [conversationId];
    let paramIndex = 2;

    if (beforeSequence) {
      query += ` AND sequence_id < $${paramIndex}`;
      params.push(parseInt(beforeSequence));
      paramIndex++;
    }

    query += ` ORDER BY sequence_id DESC LIMIT $${paramIndex}`;
    params.push(parseInt(limit));

    const result = await db.query(query, params);

    res.json({
      messages: result.rows.reverse(), // Oldest first
      hasMore: result.rows.length === parseInt(limit)
    });

  } catch (error) {
    console.error("Error fetching messages:", error);
    res.status(500).json({ message: "Failed to fetch messages" });
  }
});

// POST /messages/mark-read - Mark messages as read
router.post("/mark-read", authenticateToken, async (req, res) => {
  const { conversationId, lastReadSequenceId } = req.body;
  const userId = req.user.userId;

  if (!conversationId || !lastReadSequenceId) {
    return res.status(400).json({ message: "Conversation ID and last read sequence ID are required" });
  }

  try {
    // Verify user is part of conversation
    const [user1, user2] = conversationId.split('_');
    if (userId !== user1 && userId !== user2) {
      return res.status(403).json({ message: "Unauthorized" });
    }

    // Publish to Kafka read-receipts topic
    await producer.send({
      topic: 'read-receipts',
      messages: [{
        key: conversationId,
        value: JSON.stringify({
          conversationId,
          userId,
          lastReadSequenceId: parseInt(lastReadSequenceId),
          readAt: new Date().toISOString()
        })
      }]
    });

    res.json({ status: 'queued' });

  } catch (error) {
    console.error("Error marking as read:", error);
    res.status(500).json({ message: "Failed to mark as read" });
  }
});

// GET /messages/unread-count - Get unread message count
router.get("/unread-count", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    // Check Redis cache first
    const cached = await redis.get(`unread_count:${userId}`);
    if (cached) {
      return res.json({ unreadCount: parseInt(cached) });
    }

    // Query DB for unread messages
    const result = await db.query(`
      SELECT COUNT(*) FROM chats
      WHERE receiver_id = $1
      AND read_at IS NULL
      AND deleted_at IS NULL
    `, [userId]);

    const count = parseInt(result.rows[0].count);

    // Cache for 60 seconds
    await redis.setex(`unread_count:${userId}`, 60, count);

    res.json({ unreadCount: count });

  } catch (error) {
    console.error("Error fetching unread count:", error);
    res.status(500).json({ message: "Failed to fetch unread count" });
  }
});

// GET /messages/conversations - Get list of conversations with latest message
router.get("/conversations", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    // Query to get unique conversations with last message
    const result = await db.query(`
      WITH ranked_messages AS (
        SELECT
          conversation_id,
          sender_id,
          receiver_id,
          message,
          timestamp,
          read_at,
          ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY sequence_id DESC) as rn
        FROM chats
        WHERE (sender_id = $1 OR receiver_id = $1)
        AND deleted_at IS NULL
      )
      SELECT
        conversation_id,
        sender_id,
        receiver_id,
        message as last_message,
        timestamp as last_message_time,
        read_at
      FROM ranked_messages
      WHERE rn = 1
      ORDER BY timestamp DESC
    `, [userId]);

    res.json({ conversations: result.rows });

  } catch (error) {
    console.error("Error fetching conversations:", error);
    res.status(500).json({ message: "Failed to fetch conversations" });
  }
});

module.exports = router;
