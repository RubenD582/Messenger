//friends.js
require("dotenv").config();
const express = require("express");
const db = require("../db");
const jwt = require("jsonwebtoken");
const router = express.Router();
const { authenticateToken } = require("../middleware/authMiddleware");
const { authenticateClerkToken, enforceSingleSession } = require("../middleware/clerkMiddleware");
const rateLimit = require("express-rate-limit");

// NOTE: During migration phase, routes use old authenticateToken middleware
// After user migration is complete, replace with: authenticateClerkToken, enforceSingleSession
// Example: router.get("/search", authenticateClerkToken, enforceSingleSession, searchLimiter, async (req, res) => {
const { producer } = require('../kafkaClient');

// Use shared Redis client with Sentinel support
const redis = require('../config/redisClient');

// Rate limiter middleware
const searchLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10, // Limit each IP to 10 requests per minute
  message: 'Too many requests from this IP, please try again later.'
});

// Search Users with rate limiting
router.get("/search", authenticateToken, searchLimiter, async (req, res) => {
  const searchTerm = req.query.q;
  const userId = req.user.userId;

  if (!searchTerm || searchTerm.length < 1) {
    return res.status(400).json({ message: "Search term is required." });
  }

  try {
    const result = await db.query(
      `SELECT
        users.id,
        users.username,
        users.first_name,
        users.last_name,
        users.verified,
        users.developer,
        COALESCE(friends.status, 'not_friends') AS status,
        friends.user_id AS sender
      FROM users
      LEFT JOIN friends
        ON friends.user_id = $1 AND friends.friend_id = users.id  -- Only check one direction!
      WHERE
        (
          users.first_name ILIKE $2
          OR users.last_name ILIKE $3
          OR (users.first_name || ' ' || users.last_name) ILIKE $4
          OR users.username ILIKE $5
        )
      LIMIT 5
      `,
      [
        userId,
        `${searchTerm}%`,
        `${searchTerm}%`,
        `%${searchTerm}%`,
        `%${searchTerm}%`
      ]
    );    

    const users = result.rows;

    if (users.length === 0) {
      return res.status(404).json({ message: "No users found." });
    }

    // Format the users list to include the 'sender' field
    const formattedUsers = users.map(user => {
      return {
        ...user,
        sender: user.sender ? user.sender : null // Add sender field, if present
      };
    });

    res.json({ users: formattedUsers });
  } catch (error) {
    console.error("Error searching users:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Send Friend Request
router.post("/send-request", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const { friendId } = req.body;

  if (userId === friendId) {
    return res.status(400).json({ message: "You cannot send a request to yourself." });
  }

  const client = await db.connect();

  try {
    await client.query('BEGIN');

    // Check if already friends or pending in either direction
    const existingRelation = await client.query(
      "SELECT user_id, friend_id, status FROM friends WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)",
      [userId, friendId]
    );

    // If already friends, reject
    if (existingRelation.rows.some(r => r.status === 'accepted')) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: "Already friends." });
    }

    // Auto-merge: If other person sent request to me, accept both ways
    const reverseRequest = existingRelation.rows.find(
      r => r.user_id === friendId && r.friend_id === userId && r.status === 'pending'
    );

    if (reverseRequest) {
      // Auto-accept both sides (bidirectional friendship)
      await client.query(
        "UPDATE friends SET status = 'accepted' WHERE user_id = $1 AND friend_id = $2",
        [friendId, userId]
      );
      await client.query(
        "INSERT INTO friends (user_id, friend_id, status, created_at) VALUES ($1, $2, 'accepted', NOW())",
        [userId, friendId]
      );

      await client.query('COMMIT');

      // Invalidate cache for both users
      await invalidateCache(userId);
      await invalidateCache(friendId);

      // Clear notification deduplication keys
      await clearNotificationDedupeKeys(userId, friendId);

      // Get user names
      const userInfo = await db.query("SELECT first_name, username, verified, developer FROM users WHERE id = $1", [userId]);
      const friendInfo = await db.query("SELECT first_name, username, verified, developer FROM users WHERE id = $1", [friendId]);

      // Get updated counts
      const userCount = await db.query("SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'", [userId]);
      const friendCount = await db.query("SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'", [friendId]);

      // Notify both users via unified notification system
      await producer.send({
        topic: 'notification-creation-jobs',
        messages: [
          {
            key: String(userId),
            value: JSON.stringify({
              type: 'FRIEND_REQUEST_ACCEPTED',
              payload: {
                recipientId: userId,
                acceptorId: friendId,
                acceptorUsername: friendInfo.rows[0].username,
                acceptorVerified: friendInfo.rows[0].verified || false,
                acceptorDeveloper: friendInfo.rows[0].developer || false,
                requestCount: userCount.rows[0].count
              }
            })
          },
          {
            key: String(friendId),
            value: JSON.stringify({
              type: 'FRIEND_REQUEST_ACCEPTED',
              payload: {
                recipientId: friendId,
                acceptorId: userId,
                acceptorUsername: userInfo.rows[0].username,
                acceptorVerified: userInfo.rows[0].verified || false,
                acceptorDeveloper: userInfo.rows[0].developer || false,
                requestCount: friendCount.rows[0].count
              }
            })
          }
        ],
      });

      return res.status(201).json({ message: "Friend request auto-accepted! You are now friends.", autoAccepted: true });
    }

    // Check if I already sent a request
    if (existingRelation.rows.some(r => r.user_id === userId && r.friend_id === friendId)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: "Friend request already sent." });
    }

    // Normal flow: send new request
    await client.query(
      "INSERT INTO friends (user_id, friend_id, status, created_at) VALUES ($1, $2, 'pending', NOW())",
      [userId, friendId]
    );

    await client.query('COMMIT');

    // Get user info for notification
    const userInfo = await db.query("SELECT first_name, username, verified, developer FROM users WHERE id = $1", [userId]);
    const friendCount = await db.query(
      "SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'",
      [friendId]
    );

    // Publish unified notification event
    const notificationEvent = {
      type: 'FRIEND_REQUEST_RECEIVED',
      payload: {
        recipientId: friendId,
        senderId: userId,
        senderUsername: userInfo.rows[0].username,
        senderVerified: userInfo.rows[0].verified || false,
        senderDeveloper: userInfo.rows[0].developer || false,
        requestCount: friendCount.rows[0].count
      }
    };

    console.log(`📤 Publishing FRIEND_REQUEST_RECEIVED notification to Kafka:`, notificationEvent);

    await producer.send({
      topic: 'notification-creation-jobs',
      messages: [
        {
          key: String(friendId), // Partition by recipient
          value: JSON.stringify(notificationEvent)
        }
      ]
    });

    console.log(`✅ Friend request notification published to Kafka for user ${friendId}`);

    res.status(201).json({ message: "Friend request sent." });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error("Error sending friend request:", error);
    res.status(500).json({ message: "Server error" });
  } finally {
    client.release();
  }
});

// Accept Friend Request
router.post("/accept-request", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const { friendId } = req.body;

  const client = await db.connect();

  try {
    await client.query('BEGIN');

    const requestExists = await client.query(
      "SELECT * FROM friends WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'",
      [friendId, userId]
    );

    if (requestExists.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: "No pending friend request found." });
    }

    // Update original request to accepted
    await client.query(
      "UPDATE friends SET status = 'accepted' WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'",
      [friendId, userId]
    );

    // Create reciprocal friendship
    await client.query(
      "INSERT INTO friends (user_id, friend_id, status, created_at) VALUES ($1, $2, 'accepted', NOW())",
      [userId, friendId]
    );

    await client.query('COMMIT');

    console.log(`Friend request accepted: ${friendId} -> ${userId}`);

    // Invalidate cache for both users
    await invalidateCache(userId);
    await invalidateCache(friendId);

    // Clear notification deduplication keys to allow future interactions
    await clearNotificationDedupeKeys(userId, friendId);

    // Get user names and counts
    const receiverInfo = await db.query("SELECT first_name, username, verified, developer FROM users WHERE id = $1", [userId]);
    const senderInfo = await db.query("SELECT first_name, username, verified, developer FROM users WHERE id = $1", [friendId]);
    const receiverCount = await db.query("SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'", [userId]);
    const senderCount = await db.query("SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'", [friendId]);

    // Publish unified notification events for both users
    console.log(`📤 Publishing FRIEND_REQUEST_ACCEPTED notifications for users ${friendId} and ${userId}`);

    await producer.send({
      topic: 'notification-creation-jobs',
      messages: [
        {
          key: String(friendId), // Notify original requester
          value: JSON.stringify({
            type: 'FRIEND_REQUEST_ACCEPTED',
            payload: {
              recipientId: friendId,
              acceptorId: userId,
              acceptorUsername: receiverInfo.rows[0].username,
              acceptorVerified: receiverInfo.rows[0].verified || false,
              acceptorDeveloper: receiverInfo.rows[0].developer || false,
              requestCount: senderCount.rows[0].count
            }
          })
        },
        {
          key: String(userId), // Update badge count for acceptor
          value: JSON.stringify({
            type: 'BADGE_COUNT_UPDATE',
            payload: {
              recipientId: userId,
              requestCount: receiverCount.rows[0].count
            }
          })
        }
      ]
    });

    console.log(`✅ FRIEND_REQUEST_ACCEPTED notifications published to Kafka`);

    res.json({ message: "Friend request accepted." });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error("Error accepting friend request:", error);
    res.status(500).json({ message: "Server error" });
  } finally {
    client.release();
  }
});

// Reject Friend Request
router.post("/reject-request", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const { friendId } = req.body;

  try {
    const result = await db.query(
      "DELETE FROM friends WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'",
      [friendId, userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ message: "No pending friend request found to reject." });
    }

    // Invalidate cache since the pending list has changed
    await invalidateCache(userId);

    // Clear notification deduplication keys to allow future requests
    await clearNotificationDedupeKeys(userId, friendId);

    res.status(200).json({ message: "Friend request rejected." });
  } catch (error) {
    console.error("Error rejecting friend request:", error);
    res.status(500).json({ message: "Server error" });
  }
});


// Reject or Remove Friend
router.post("/remove", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const { friendId } = req.body;

  try {
    const result = await db.query(
      "DELETE FROM friends WHERE (user_id = $1 AND friend_id = $2 AND status = 'accepted') OR (user_id = $2 AND friend_id = $1 AND status = 'accepted')",
      [userId, friendId]
    );

    if (result.rowCount === 0) {
      return res.status(400).json({ message: "No friendship found or not authorized to remove." });
    }

    // Publish friend removal event to Kafka
    await producer.send({
      topic: 'friend-events',
      messages: [
        { 
          key: String(friendId), 
          value: JSON.stringify({
            event: 'friendRemoved',
            payload: {
              userId: userId,
              friendId: friendId,
              timestamp: new Date().toISOString()
            }
          })
        },
      ],
    });

    res.json({ message: "Friend removed successfully." });
  } catch (error) {
    console.error("Error removing friend:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Get Pending Friend Requests
router.get("/pending-requests", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  try {
    // Try to get from Redis cache first
    const cachedPendingRequests = await redis.get(`pending_requests:${userId}`);
    
    if (cachedPendingRequests) {
      return res.json({ pendingRequests: JSON.parse(cachedPendingRequests) });
    }
    
    // If not in cache, get from database
    const pendingRequests = await db.query(
      "SELECT users.id, users.username, users.first_name, users.last_name, friends.created_at FROM friends JOIN users ON users.id = friends.user_id WHERE friends.friend_id = $1 AND friends.status = 'pending'",
      [userId]
    );
    
    // Cache the result with 5 minute expiry
    await redis.setex(`pending_requests:${userId}`, 300, JSON.stringify(pendingRequests.rows));
    
    res.json({ pendingRequests: pendingRequests.rows });
  } catch (error) {
    console.error("Error fetching pending friend requests:", error);
    res.status(500).json({ message: "Server error" });
  }
});

router.get("/pending-requests/count", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    // Try to get from Redis cache first
    const cachedCount = await redis.get(`pending_requests_count:${userId}`);
    
    if (cachedCount !== null) {
      return res.json({ pendingCount: parseInt(cachedCount) });
    }
    
    // If not in cache, get from database
    const result = await db.query(
      "SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'",
      [userId]
    );
    
    const count = parseInt(result.rows[0].count);
    
    // Cache the result with 5 minute expiry
    await redis.setex(`pending_requests_count:${userId}`, 300, count.toString());
    
    res.json({ pendingCount: count });
  } catch (error) {
    console.error("Error fetching pending request count:", error);
    res.status(500).json({ message: "Server error" });
  }
});

router.get("/list", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  let { lastFetched, clientVersion, status = 'accepted' } = req.query;

  try {
    // Comprehensive friends query with soft delete and versioning
    let query = `
      SELECT
        users.id AS friend_id,
        users.username,
        users.first_name,
        users.last_name,
        users.verified,
        users.developer,
        friends.created_at,
        CASE
          WHEN friends.deleted_at IS NOT NULL THEN 'deleted'
          ELSE 'active'
        END AS friend_status
      FROM friends
      JOIN users ON users.id = friends.friend_id
      WHERE
        friends.user_id = $1
        AND friends.status = $2
        AND (friends.deleted_at IS NULL OR friends.deleted_at > NOW() - INTERVAL '30 days')`;

    let params = [userId, status];
    let paramIndex = 3;

    // Timestamp-based filtering
    if (lastFetched && lastFetched !== "null" && !isNaN(Date.parse(lastFetched))) {
      query += ` AND friends.created_at > $${paramIndex}`;
      params.push(new Date(lastFetched).toISOString());
      paramIndex++;
    }

    // Version-based filtering if client provides version
    if (clientVersion) {
      query += ` AND friends.version > $${paramIndex}`;
      params.push(parseInt(clientVersion, 10));
    }

    const friends = await db.query(query, params);

    // Generate server-side version
    const serverVersion = Math.floor(Date.now() / 1000);

    // Cache with enhanced metadata
    const cacheKey = `friends_list:${userId}:${status}`;
    await redis.setex(cacheKey, 600, JSON.stringify({
      friends: friends.rows,
      version: serverVersion
    }));

    res.json({ 
      friends: friends.rows,
      serverTimestamp: new Date().toISOString(),
      version: serverVersion
    });
  } catch (error) {
    console.error("Error fetching friends:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Enhanced delete route with soft delete
router.delete("/friends/:friendId", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const friendId = req.params.friendId;

  try {
    const deleteQuery = `
      UPDATE friends 
      SET 
        deleted_at = NOW(), 
        version = EXTRACT(EPOCH FROM NOW())::INTEGER 
      WHERE 
        user_id = $1 AND friend_id = $2 AND deleted_at IS NULL
    `;

    const result = await db.query(deleteQuery, [userId, friendId]);

    if (result.rowCount > 0) {
      res.status(200).json({ message: "Friend removed successfully" });
    } else {
      res.status(404).json({ message: "Friend not found" });
    }
  } catch (error) {
    console.error("Error deleting friend:", error);
    res.status(500).json({ message: "Server error" });
  }
});


// Optimized cache invalidation using specific key patterns
const invalidateCache = async (userId) => {
  try {
    // Use specific key patterns instead of wildcard matching
    const keysToDelete = [
      `pending_requests:${userId}`,
      `pending_requests_count:${userId}`,
      `friends_list:${userId}:accepted`,
      `friends_list:${userId}:pending`
    ];

    // Delete keys that exist
    const pipeline = redis.pipeline();
    keysToDelete.forEach(key => pipeline.del(key));
    await pipeline.exec();

    console.log(`Cache invalidated for user ${userId} (${keysToDelete.length} specific keys)`);
  } catch (error) {
    console.error(`Error invalidating cache for user ${userId}:`, error);
  }
};

// Removed queueOfflineNotification - now handled by unified notification service

// Clear notification deduplication keys between two users
const clearNotificationDedupeKeys = async (userId1, userId2) => {
  try {
    const keysToDelete = [
      `notif_dedup:${userId1}:FRIEND_REQUEST_RECEIVED:${userId2}`,
      `notif_dedup:${userId1}:FRIEND_REQUEST_ACCEPTED:${userId2}`,
      `notif_dedup:${userId2}:FRIEND_REQUEST_RECEIVED:${userId1}`,
      `notif_dedup:${userId2}:FRIEND_REQUEST_ACCEPTED:${userId1}`
    ];

    const pipeline = redis.pipeline();
    keysToDelete.forEach(key => pipeline.del(key));
    await pipeline.exec();

    console.log(`Cleared notification dedupe keys between ${userId1} and ${userId2}`);
  } catch (error) {
    console.error(`Error clearing notification dedupe keys:`, error);
  }
};

// Graceful shutdown
process.on('SIGTERM', async () => {
  try {
    await producer.disconnect();
    await redis.quit();
    console.log('Gracefully disconnected from Kafka and Redis');
    process.exit(0);
  } catch (error) {
    console.error('Error during graceful shutdown:', error);
    process.exit(1);
  }
});

module.exports = router;