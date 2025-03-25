//friends.js
require("dotenv").config();
const express = require("express");
const db = require("../db");
const jwt = require("jsonwebtoken");
const router = express.Router();
const { authenticateToken } = require("../middleware/authMiddleware");
const rateLimit = require("express-rate-limit");
const Redis = require('ioredis');
const { producer } = require('../kafkaClient');

// Initialize Redis client
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis',
  port: process.env.REDIS_PORT || 6379
});

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

  try {
    const existingRequest = await db.query(
      "SELECT created_at FROM friends WHERE user_id = $1 AND friend_id = $2",
      [userId, friendId]
    );

    if (existingRequest.rows.length > 0) {
      return res.status(400).json({ message: "Friend request already sent." });
    }

    await db.query(
      "INSERT INTO friends (user_id, friend_id, status, created_at) VALUES ($1, $2, 'pending', NOW())",
      [userId, friendId]
    );

    // Get user info for notification
    const userInfo = await db.query(
      "SELECT first_name FROM users WHERE id = $1",
      [userId]
    );

    // Get amount of friend request
    const friendCount = await db.query(
      "SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'",
      [userId]
    );

    let newFriendCount = parseFloat(friendCount.rows[0].count) + 1;
    
    // Publish friend request event to Kafka
    await producer.send({
      topic: 'friend-events',
      messages: [
        { 
          key: String(friendId), 
          value: JSON.stringify({
            event: 'newFriendRequest',
            payload: {
              senderId: userId,
              senderName: userInfo.rows[0].first_name,
              requestCount: newFriendCount,
              timestamp: new Date().toISOString()
            }
          })
        },
      ],
    });
    
    console.log(`Friend request event published to Kafka for user ${friendId}`);

    res.status(201).json({ message: "Friend request sent." });
  } catch (error) {
    console.error("Error sending friend request:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Accept Friend Request
router.post("/accept-request", authenticateToken, async (req, res) => {
  const userId = req.user.userId;
  const { friendId } = req.body;

  try {
    const requestExists = await db.query(
      "SELECT * FROM friends WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'",
      [friendId, userId]
    );

    if (requestExists.rows.length === 0) {
      return res.status(400).json({ message: "No pending friend request found." });
    }

    // A send to B friend request
    await db.query(
      "UPDATE friends SET status = 'accepted' WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'",
      [friendId, userId]
    ); 
    // This cause B to sent friend request to A
    await db.query(
      "INSERT INTO friends (user_id, friend_id, status, created_at) VALUES ($1, $2, 'accepted', NOW())",
      [userId, friendId]
    );

    console.log(`Friend request accepted: ${friendId} -> ${userId}`);

    // Invalidate cache for both users
    await invalidateCache(userId);
    await invalidateCache(friendId);

    // Display the name of the person who accepted the friend request
    const receiverName = await db.query(
      "SELECT first_name FROM users WHERE id = $1",
      [userId]
    );
    const receiverFriendCount = await db.query(
      "SELECT COUNT(*) FROM friends WHERE friend_id = $1 AND status = 'pending'",
      [userId]
    );

    // Publish friend acceptance event to Kafka
    await producer.send({
      topic: 'friend-events',
      messages: [
        {
          key: String(userId),
          value: JSON.stringify({
            event: 'friendRequestAccepted',
            payload: {
              userId: userId,
              friendId: friendId,
              friendName: receiverName.rows[0].first_name,
              requestCount: receiverFriendCount.rows[0].count,
              timestamp: new Date().toISOString()
            }
          })
        },
      ],
    });


    res.json({ message: "Friend request accepted." });
  } catch (error) {
    console.error("Error accepting friend request:", error);
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
      "SELECT users.id, users.username, users.first_name, users.last_name FROM friends JOIN users ON users.id = friends.user_id WHERE friends.friend_id = $1 AND friends.status = 'pending'",
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
  let { lastFetched } = req.query;
  let { status } = req.query || 'accepted';

  console.log(`Fetching for: ${userId}`);

  try {
    let query = `
      SELECT users.id AS friend_id, users.username, users.first_name, users.last_name, friends.created_at
      FROM friends 
      JOIN users ON users.id = friends.friend_id 
      WHERE friends.user_id = $1 AND friends.status = $2`;

    let params = [userId, status];

    // Validate lastFetched
    if (lastFetched && lastFetched !== "null" && !isNaN(Date.parse(lastFetched))) {
      query += ` AND friends.created_at > $3`;
      params.push(new Date(lastFetched).toISOString()); // Ensure it's a valid timestamp
    }

    const friends = await db.query(query, params);
    console.log(`Fetching ${friends.rows}`)

    // Cache the result with 10-minute expiry
    await redis.setex(`friends_list:${userId}`, 600, JSON.stringify(friends.rows));

    res.json({ 
      friends: friends.rows,
      serverTimestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error("Error fetching friends:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Add an invalidate cache helper function
const invalidateCache = async (userId) => {
  try {
    await Promise.all([
      redis.del(`pending_requests:${userId}`),
      redis.del(`pending_requests_count:${userId}`),
      redis.del(`friends_list:${userId}`)
    ]);
    console.log(`Cache invalidated for user ${userId}`);
  } catch (error) {
    console.error(`Error invalidating cache for user ${userId}:`, error);
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