// statuses.js
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const { userRateLimiter } = require("../middleware/userRateLimiter");
const { v4: uuidv4 } = require('uuid');
const { producer } = require('../kafkaClient');

// POST /statuses - Create a new status
router.post("/", authenticateToken, userRateLimiter, async (req, res) => {
  const { textContent, backgroundColor } = req.body;
  const userId = req.user.userId;

  if (!textContent || !backgroundColor) {
    return res.status(400).json({ message: "Text content and background color are required" });
  }

  // Validate hex color format
  const hexColorRegex = /^#[0-9A-Fa-f]{6}$/;
  if (!hexColorRegex.test(backgroundColor)) {
    return res.status(400).json({ message: "Invalid background color format. Use hex format (#RRGGBB)" });
  }

  try {
    const statusId = uuidv4();
    const now = new Date();

    // Insert into database
    const result = await db.query(`
      INSERT INTO statuses (id, user_id, text_content, background_color, created_at)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id, user_id, text_content, background_color, created_at
    `, [statusId, userId, textContent, backgroundColor, now]);

    const status = result.rows[0];

    // Get user info for the response and WebSocket event
    const userResult = await db.query(`
      SELECT first_name, last_name, username FROM users WHERE id = $1
    `, [userId]);

    const user = userResult.rows[0];

    const statusWithUser = {
      id: status.id,
      userId: status.user_id,
      userName: `${user.first_name} ${user.last_name}`.trim(),
      username: user.username,
      textContent: status.text_content,
      backgroundColor: status.background_color,
      createdAt: status.created_at
    };

    // Publish to Kafka for WebSocket broadcast to friends
    await producer.send({
      topic: 'status-events',
      messages: [{
        key: userId,
        value: JSON.stringify({
          event: 'statusCreated',
          data: statusWithUser
        })
      }]
    });

    res.status(201).json(statusWithUser);

  } catch (error) {
    console.error("Error creating status:", error);
    res.status(500).json({ message: "Failed to create status" });
  }
});

// GET /statuses/friends - Get statuses from friends (active within 24 hours)
router.get("/friends", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    // Query statuses from accepted friends, created within last 24 hours
    const result = await db.query(`
      SELECT
        s.id,
        s.user_id,
        s.text_content,
        s.background_color,
        s.created_at,
        u.first_name,
        u.last_name,
        u.username
      FROM statuses s
      INNER JOIN users u ON s.user_id = u.id
      INNER JOIN friends f ON (
        (f.user_id = $1 AND f.friend_id = s.user_id)
        OR (f.friend_id = $1 AND f.user_id = s.user_id)
      )
      WHERE f.status = 'accepted'
      AND s.created_at > NOW() - INTERVAL '24 hours'
      ORDER BY s.created_at DESC
    `, [userId]);

    const statuses = result.rows.map(row => ({
      id: row.id,
      userId: row.user_id,
      userName: `${row.first_name} ${row.last_name}`.trim(),
      username: row.username,
      textContent: row.text_content,
      backgroundColor: row.background_color,
      createdAt: row.created_at
    }));

    res.json({ statuses });

  } catch (error) {
    console.error("Error fetching friend statuses:", error);
    res.status(500).json({ message: "Failed to fetch friend statuses" });
  }
});

// GET /statuses/me - Get current user's active statuses (up to 20)
router.get("/me", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    const result = await db.query(`
      SELECT
        s.id,
        s.user_id,
        s.text_content,
        s.background_color,
        s.created_at,
        u.first_name,
        u.last_name,
        u.username
      FROM statuses s
      INNER JOIN users u ON s.user_id = u.id
      WHERE s.user_id = $1
      AND s.created_at > NOW() - INTERVAL '24 hours'
      ORDER BY s.created_at ASC
      LIMIT 20
    `, [userId]);

    const statuses = result.rows.map(row => ({
      id: row.id,
      userId: row.user_id,
      userName: `${row.first_name} ${row.last_name}`.trim(),
      username: row.username,
      textContent: row.text_content,
      backgroundColor: row.background_color,
      createdAt: row.created_at
    }));

    res.json({ statuses });

  } catch (error) {
    console.error("Error fetching user statuses:", error);
    res.status(500).json({ message: "Failed to fetch user statuses" });
  }
});

// DELETE /statuses/:id - Delete own status
router.delete("/:id", authenticateToken, async (req, res) => {
  const { id } = req.params;
  const userId = req.user.userId;

  try {
    // Verify ownership and delete
    const result = await db.query(`
      DELETE FROM statuses
      WHERE id = $1 AND user_id = $2
      RETURNING id
    `, [id, userId]);

    if (result.rowCount === 0) {
      return res.status(404).json({ message: "Status not found or unauthorized" });
    }

    // Publish to Kafka for WebSocket broadcast
    await producer.send({
      topic: 'status-events',
      messages: [{
        key: userId,
        value: JSON.stringify({
          event: 'statusDeleted',
          data: { id, userId }
        })
      }]
    });

    res.json({ message: "Status deleted successfully" });

  } catch (error) {
    console.error("Error deleting status:", error);
    res.status(500).json({ message: "Failed to delete status" });
  }
});

module.exports = router;
