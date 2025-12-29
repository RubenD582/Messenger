//messages.js
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const { authenticateClerkToken, enforceSingleSession } = require("../middleware/clerkMiddleware");
const { producer } = require('../kafkaClient');

// NOTE: During migration phase, routes use old authenticateToken middleware
// After user migration is complete, replace with: authenticateClerkToken, enforceSingleSession
// Example: router.post("/send", authenticateClerkToken, enforceSingleSession, async (req, res) => {
const { v4: uuidv4 } = require('uuid');

// Use shared Redis client with Sentinel support
const redis = require('../config/redisClient');

// Helper: Generate conversation ID (deterministic)
function getConversationId(userId1, userId2) {
  const sorted = [userId1, userId2].sort();
  return `${sorted[0]}_${sorted[1]}`;
}

// POST /messages/send - Send a message (supports regular messages and drawings)
router.post("/send", authenticateToken, async (req, res) => {
  const {
    receiverId,
    message,
    messageType = 'text',
    metadata = {},
    positionX,
    positionY,
    isPositioned = false
  } = req.body;
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
      metadata,
      // Position data for positioned messages and drawings
      positionX: positionX !== undefined ? positionX : null,
      positionY: positionY !== undefined ? positionY : null,
      isPositioned: isPositioned || false
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
        conversation_id,
        position_x,
        position_y,
        is_positioned,
        positioned_by,
        positioned_at,
        rotation,
        scale
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

// DELETE /messages/conversation/:conversationId - Delete conversation for BOTH users (Snapchat-style)
router.delete("/conversation/:conversationId", authenticateToken, async (req, res) => {
  const { conversationId } = req.params;
  const userId = req.user.userId;
  const { userName } = req.body; // Optional: user's display name

  try {
    // Verify user is part of conversation
    const [user1, user2] = conversationId.split('_');
    if (userId !== user1 && userId !== user2) {
      return res.status(403).json({ message: "Unauthorized" });
    }

    const now = new Date().toISOString();

    // Get user's name from database
    const userResult = await db.query(`
      SELECT first_name, last_name FROM users WHERE id = $1
    `, [userId]);
    const displayName = userResult.rows[0]
      ? `${userResult.rows[0].first_name} ${userResult.rows[0].last_name}`.trim()
      : 'Someone';

    // Soft delete all messages in conversation for BOTH users
    const deleteResult = await db.query(`
      UPDATE chats
      SET deleted_at = $1
      WHERE conversation_id = $2
      AND deleted_at IS NULL
    `, [now, conversationId]);

    console.log(`✅ ${displayName} deleted conversation ${conversationId}: ${deleteResult.rowCount} messages (for both users)`);

    // Create a system message: "User cleared the chat"
    // This helps both users understand what happened
    const systemMessageId = require('uuid').v4();
    const otherUserId = userId === user1 ? user2 : user1;

    // Get next sequence ID from Redis
    const redis = require('../config/redisClient');
    const sequenceId = await redis.incr(`conversation_seq:${conversationId}`);

    await db.query(`
      INSERT INTO chats (
        message_id, conversation_id, sender_id, receiver_id,
        message, sequence_id, timestamp, message_type, metadata
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    `, [
      systemMessageId,
      conversationId,
      userId,
      otherUserId,
      `${displayName} cleared the chat`,
      sequenceId,
      now,
      'system',
      JSON.stringify({ action: 'chat_cleared', clearedBy: userId })
    ]);

    // Publish system message to Kafka so it's broadcast to both users
    const systemMessageData = {
      messageId: systemMessageId,
      conversationId,
      senderId: userId,
      receiverId: otherUserId,
      message: `${displayName} cleared the chat`,
      messageType: 'system',
      sequenceId,
      timestamp: now,
      metadata: { action: 'chat_cleared', clearedBy: userId }
    };

    await producer.send({
      topic: 'chat-messages',
      messages: [{
        key: conversationId,
        value: JSON.stringify(systemMessageData)
      }]
    });

    res.json({
      message: "Conversation deleted successfully (for both users)",
      deletedCount: deleteResult.rowCount,
      systemMessageId
    });

  } catch (error) {
    console.error("Error deleting conversation:", error);
    res.status(500).json({ message: "Failed to delete conversation" });
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
