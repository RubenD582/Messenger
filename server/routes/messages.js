//messages.js
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const { userRateLimiter } = require("../middleware/userRateLimiter");
const { v4: uuidv4 } = require('uuid');
const redis = require('../config/redisClient');
const { producer } = require('../kafkaClient');

// Helper function to generate conversation ID from two user IDs
function getConversationId(userId1, userId2) {
  return [userId1, userId2].sort().join('_');
}

// POST /messages/send - Send a message (supports regular messages and drawings)
router.post("/send", authenticateToken, userRateLimiter, async (req, res) => {
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

    // Invalidate friends overview cache for both users
    await redis.del(`friends_overview:${senderId}`);
    await redis.del(`friends_overview:${receiverId}`);

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
router.get("/history/:conversationId", authenticateToken, userRateLimiter, async (req, res) => {
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

    console.log(`📥 Fetching history for ${conversationId}: Found ${result.rows.length} messages`);
    if (result.rows.length > 0) {
      console.log(`   Latest sequence ID: ${result.rows[0].sequence_id}`);
      console.log(`   Oldest sequence ID: ${result.rows[result.rows.length - 1].sequence_id}`);
    }

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

    // Invalidate friends overview cache
    await redis.del(`friends_overview:${userId}`);

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
    await redis.set(`unread_count:${userId}`, count.toString(), 'EX', 60);

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

    // Use ON CONFLICT DO NOTHING to avoid duplicate key errors
    await db.query(`
      INSERT INTO chats (
        message_id, conversation_id, sender_id, receiver_id,
        message, sequence_id, timestamp, message_type, metadata
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (conversation_id, sequence_id) DO NOTHING
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

// GET /messages/friends-overview - Optimized endpoint for friends list with message preview
router.get("/friends-overview", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    // Check Redis cache first (5 minute cache)
    const cacheKey = `friends_overview:${userId}`;
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // Optimized query using CTEs and proper indexes
    const result = await db.query(`
      WITH friend_conversations AS (
        -- Get all friends with their conversation IDs
        SELECT
          f.friend_id,
          CASE
            WHEN $1 < f.friend_id THEN $1 || '_' || f.friend_id
            ELSE f.friend_id || '_' || $1
          END as conversation_id
        FROM friends f
        WHERE f.user_id = $1 AND f.status = 'accepted'
      ),
      last_messages AS (
        -- Get the last message for each conversation
        SELECT DISTINCT ON (c.conversation_id)
          c.conversation_id,
          c.message,
          c.message_type,
          c.timestamp,
          c.sender_id,
          c.metadata
        FROM chats c
        INNER JOIN friend_conversations fc ON fc.conversation_id = c.conversation_id
        WHERE c.deleted_at IS NULL
        ORDER BY c.conversation_id, c.sequence_id DESC
      ),
      unread_counts AS (
        -- Count unread messages per conversation
        SELECT
          c.conversation_id,
          COUNT(*) as unread_count
        FROM chats c
        INNER JOIN friend_conversations fc ON fc.conversation_id = c.conversation_id
        WHERE c.receiver_id = $1
          AND c.read_at IS NULL
          AND c.deleted_at IS NULL
        GROUP BY c.conversation_id
      )
      SELECT
        fc.friend_id,
        fc.conversation_id,
        lm.message as last_message,
        lm.message_type,
        lm.timestamp as last_message_timestamp,
        lm.sender_id as last_message_sender_id,
        lm.metadata as last_message_metadata,
        COALESCE(uc.unread_count, 0) as unread_count
      FROM friend_conversations fc
      LEFT JOIN last_messages lm ON lm.conversation_id = fc.conversation_id
      LEFT JOIN unread_counts uc ON uc.conversation_id = fc.conversation_id
      ORDER BY
        CASE WHEN lm.timestamp IS NULL THEN 1 ELSE 0 END,
        lm.timestamp DESC NULLS LAST
    `, [userId]);

    const overview = {
      friends: result.rows,
      timestamp: new Date().toISOString()
    };

    // Cache for 5 minutes
    await redis.set(cacheKey, JSON.stringify(overview), 'EX', 300);

    res.json(overview);

  } catch (error) {
    console.error("Error fetching friends overview:", error);
    res.status(500).json({ message: "Failed to fetch friends overview" });
  }
});

// Sync endpoint - fetch missed updates for a conversation
router.get("/sync/:conversationId", authenticateToken, async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { after } = req.query; // ISO timestamp of last sync
    const userId = req.user.userId;

    console.log(`🔄 Sync request for ${conversationId} after ${after || 'beginning'}`);

    // Verify user is part of this conversation
    const [user1, user2] = conversationId.split('_').sort();
    if (userId !== user1 && userId !== user2) {
      return res.status(403).json({ message: "Unauthorized" });
    }

    // Get messages after the specified timestamp
    const messagesQuery = after
      ? `SELECT
          message_id, conversation_id, sender_id, receiver_id,
          message, sequence_id, timestamp, message_type, metadata,
          read_at, delivered_at, is_positioned, position_x, position_y,
          positioned_by, positioned_at, rotation, scale
         FROM chats
         WHERE conversation_id = $1
           AND timestamp > $2
           AND deleted_at IS NULL
         ORDER BY sequence_id ASC`
      : `SELECT
          message_id, conversation_id, sender_id, receiver_id,
          message, sequence_id, timestamp, message_type, metadata,
          read_at, delivered_at, is_positioned, position_x, position_y,
          positioned_by, positioned_at, rotation, scale
         FROM chats
         WHERE conversation_id = $1
           AND deleted_at IS NULL
         ORDER BY sequence_id ASC`;

    const messagesParams = after ? [conversationId, after] : [conversationId];
    const messages = await db.query(messagesQuery, messagesParams);

    // Get deleted message IDs since last sync
    const deletedQuery = after
      ? `SELECT message_id, deleted_at
         FROM chats
         WHERE conversation_id = $1
           AND deleted_at IS NOT NULL
           AND deleted_at > $2`
      : `SELECT message_id, deleted_at
         FROM chats
         WHERE conversation_id = $1
           AND deleted_at IS NOT NULL`;

    const deletedParams = after ? [conversationId, after] : [conversationId];
    const deleted = await db.query(deletedQuery, deletedParams);

    // Check if chat was cleared (look for system message with chat_cleared action)
    const chatClearedQuery = after
      ? `SELECT metadata, timestamp
         FROM chats
         WHERE conversation_id = $1
           AND message_type = 'system'
           AND metadata::json->>'action' = 'chat_cleared'
           AND timestamp > $2
         ORDER BY timestamp DESC
         LIMIT 1`
      : null;

    let chatCleared = false;
    let chatClearedAt = null;

    if (chatClearedQuery && after) {
      const clearedResult = await db.query(chatClearedQuery, [conversationId, after]);
      if (clearedResult.rows.length > 0) {
        chatCleared = true;
        chatClearedAt = clearedResult.rows[0].timestamp;
      }
    }

    // Get last sequence ID
    const lastSeqResult = await db.query(
      `SELECT MAX(sequence_id) as last_seq
       FROM chats
       WHERE conversation_id = $1
         AND deleted_at IS NULL`,
      [conversationId]
    );

    const lastSequenceId = lastSeqResult.rows[0]?.last_seq || 0;

    console.log(`✅ Sync for ${conversationId}: ${messages.rows.length} messages, ${deleted.rows.length} deleted, cleared: ${chatCleared}`);

    res.json({
      messages: messages.rows,
      deletedMessageIds: deleted.rows.map(r => r.message_id),
      chatCleared,
      chatClearedAt,
      lastSequenceId,
      syncTimestamp: new Date().toISOString(),
    });

  } catch (error) {
    console.error("Error syncing conversation:", error);
    res.status(500).json({ message: "Failed to sync conversation" });
  }
});

module.exports = router;
