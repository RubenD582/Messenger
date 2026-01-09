// remixes.js - Daily Remix API routes
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const multer = require('multer');
const imageStorage = require('../services/imageStorage');
const { producer } = require('../kafkaClient');

// Configure multer for memory storage (we'll process with sharp)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
  },
  fileFilter: (req, file, cb) => {
    // Accept images only
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image files are allowed'), false);
    }
    cb(null, true);
  },
});

// Initialize image storage
imageStorage.init().catch(console.error);

// ============================================
// GROUP MANAGEMENT
// ============================================

// POST /remixes/groups - Create a new remix group
router.post("/groups", authenticateToken, async (req, res) => {
  const { name, memberIds } = req.body;
  const userId = req.user.userId;

  if (!memberIds || !Array.isArray(memberIds) || memberIds.length === 0) {
    return res.status(400).json({ message: "Member IDs required" });
  }

  // Limit group size (3-5 members including creator)
  if (memberIds.length > 4 || memberIds.length < 2) {
    return res.status(400).json({ message: "Groups must have 3-5 members" });
  }

  try {
    // Create group
    const groupResult = await db.query(`
      INSERT INTO remix_groups (name, created_by)
      VALUES ($1, $2)
      RETURNING *
    `, [name || 'My Remix Group', userId]);

    const groupId = groupResult.rows[0].id;

    // Add creator as member
    await db.query(`
      INSERT INTO remix_group_members (group_id, user_id)
      VALUES ($1, $2)
    `, [groupId, userId]);

    // Add other members
    for (const memberId of memberIds) {
      await db.query(`
        INSERT INTO remix_group_members (group_id, user_id)
        VALUES ($1, $2)
        ON CONFLICT (group_id, user_id) DO NOTHING
      `, [groupId, memberId]);
    }

    res.status(201).json({
      message: "Group created successfully",
      group: groupResult.rows[0],
    });

    console.log(`✅ Created remix group ${groupId} with ${memberIds.length + 1} members`);

  } catch (error) {
    console.error("Error creating remix group:", error);
    res.status(500).json({ message: "Failed to create group" });
  }
});

// GET /remixes/groups - Get user's remix groups
router.get("/groups", authenticateToken, async (req, res) => {
  const userId = req.user.userId;

  try {
    const result = await db.query(`
      SELECT
        rg.*,
        COUNT(DISTINCT rgm.user_id) as member_count,
        MAX(rp.post_date) as last_post_date
      FROM remix_groups rg
      INNER JOIN remix_group_members rgm ON rg.id = rgm.group_id
      LEFT JOIN remix_posts rp ON rg.id = rp.group_id
      WHERE rg.id IN (
        SELECT group_id FROM remix_group_members WHERE user_id = $1
      )
      AND rg.is_active = true
      GROUP BY rg.id
      ORDER BY last_post_date DESC NULLS LAST
    `, [userId]);

    res.json({ groups: result.rows });

  } catch (error) {
    console.error("Error fetching remix groups:", error);
    res.status(500).json({ message: "Failed to fetch groups" });
  }
});

// GET /remixes/groups/:groupId/members - Get group members
router.get("/groups/:groupId/members", authenticateToken, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    // Verify user is in the group
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    // Get members with user details
    const result = await db.query(`
      SELECT
        u.id,
        u.first_name,
        u.last_name,
        u.username,
        rgm.streak_count,
        rgm.joined_at
      FROM remix_group_members rgm
      INNER JOIN users u ON rgm.user_id = u.id
      WHERE rgm.group_id = $1
      ORDER BY rgm.joined_at
    `, [groupId]);

    res.json({ members: result.rows });

  } catch (error) {
    console.error("Error fetching group members:", error);
    res.status(500).json({ message: "Failed to fetch members" });
  }
});

// ============================================
// POSTS (BASE PHOTOS)
// ============================================

// POST /remixes/posts - Create a new remix post (base photo)
router.post("/posts", authenticateToken, upload.single('image'), async (req, res) => {
  const { groupId, theme } = req.body;
  const userId = req.user.userId;

  if (!req.file) {
    return res.status(400).json({ message: "Image required" });
  }

  if (!groupId) {
    return res.status(400).json({ message: "Group ID required" });
  }

  try {
    // Verify user is in the group
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    // Check if post already exists for today
    const today = new Date().toISOString().split('T')[0];
    const existingPost = await db.query(`
      SELECT id FROM remix_posts
      WHERE group_id = $1 AND post_date = $2
    `, [groupId, today]);

    if (existingPost.rows.length > 0) {
      return res.status(400).json({ message: "Post already exists for today" });
    }

    // Upload and compress image
    const imageData = await imageStorage.uploadImage(req.file.buffer);

    // Calculate expiration (12 hours from now)
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 12);

    // Create post
    const result = await db.query(`
      INSERT INTO remix_posts (
        group_id, posted_by, post_date,
        image_url, thumbnail_url,
        image_width, image_height,
        theme, expires_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *
    `, [
      groupId,
      userId,
      today,
      imageData.originalUrl,
      imageData.thumbnailUrl,
      imageData.width,
      imageData.height,
      theme || null,
      expiresAt
    ]);

    const post = result.rows[0];

    // Publish to Kafka for real-time updates
    await producer.send({
      topic: 'remix-updates',
      messages: [{
        key: groupId,
        value: JSON.stringify({
          type: 'new_post',
          groupId,
          post,
          postedBy: userId
        })
      }]
    });

    res.status(201).json({
      message: "Post created successfully",
      post,
    });

    console.log(`✅ Created remix post for group ${groupId}`);

  } catch (error) {
    console.error("Error creating remix post:", error);
    res.status(500).json({ message: "Failed to create post" });
  }
});

// GET /remixes/posts/:groupId/today - Get today's post for a group
router.get("/posts/:groupId/today", authenticateToken, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    // Verify user is in the group
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    const today = new Date().toISOString().split('T')[0];

    // Get today's post with layer count
    const result = await db.query(`
      SELECT
        rp.*,
        u.first_name,
        u.last_name,
        COUNT(rl.id) as layer_count
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
      LEFT JOIN remix_layers rl ON rp.id = rl.post_id
      WHERE rp.group_id = $1 AND rp.post_date = $2
      GROUP BY rp.id, u.first_name, u.last_name
    `, [groupId, today]);

    if (result.rows.length === 0) {
      return res.json({ post: null });
    }

    res.json({ post: result.rows[0] });

  } catch (error) {
    console.error("Error fetching today's post:", error);
    res.status(500).json({ message: "Failed to fetch post" });
  }
});

// GET /remixes/posts/:groupId/history - Get past posts for a group
router.get("/posts/:groupId/history", authenticateToken, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  const { limit = 7, offset = 0 } = req.query;

  try {
    // Verify user is in the group
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    // Get past posts (not including today)
    const today = new Date().toISOString().split('T')[0];
    const result = await db.query(`
      SELECT
        rp.*,
        u.first_name,
        u.last_name,
        COUNT(rl.id) as layer_count
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
      LEFT JOIN remix_layers rl ON rp.id = rl.post_id
      WHERE rp.group_id = $1 AND rp.post_date < $2
      GROUP BY rp.id, u.first_name, u.last_name
      ORDER BY rp.post_date DESC
      LIMIT $3 OFFSET $4
    `, [groupId, today, parseInt(limit), parseInt(offset)]);

    res.json({ posts: result.rows });

  } catch (error) {
    console.error("Error fetching post history:", error);
    res.status(500).json({ message: "Failed to fetch history" });
  }
});

// ============================================
// LAYERS (ADDITIONS TO POSTS)
// ============================================

// POST /remixes/layers - Add a layer to a post
router.post("/layers", authenticateToken, upload.single('image'), async (req, res) => {
  const {
    postId,
    layerType,
    textContent,
    stickerData,
    positionX = 0.5,
    positionY = 0.5,
    scale = 1.0,
    rotation = 0,
    metadata
  } = req.body;
  const userId = req.user.userId;

  if (!postId || !layerType) {
    return res.status(400).json({ message: "Post ID and layer type required" });
  }

  try {
    // Verify post exists and user is in the group
    const postCheck = await db.query(`
      SELECT rp.id, rp.group_id, rp.expires_at
      FROM remix_posts rp
      INNER JOIN remix_group_members rgm
        ON rp.group_id = rgm.group_id AND rgm.user_id = $1
      WHERE rp.id = $2
    `, [userId, postId]);

    if (postCheck.rows.length === 0) {
      return res.status(403).json({ message: "Post not found or not authorized" });
    }

    const post = postCheck.rows[0];

    // Check if post has expired
    if (new Date() > new Date(post.expires_at)) {
      return res.status(400).json({ message: "Post has expired" });
    }

    let contentUrl = null;

    // Handle image upload for photo layers
    if (layerType === 'photo' && req.file) {
      const imageData = await imageStorage.uploadImage(req.file.buffer);
      contentUrl = imageData.originalUrl;
    }

    // Insert layer
    const result = await db.query(`
      INSERT INTO remix_layers (
        post_id, added_by, layer_type,
        content_url, text_content, sticker_data,
        position_x, position_y, scale, rotation,
        metadata
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *
    `, [
      postId,
      userId,
      layerType,
      contentUrl,
      textContent || null,
      stickerData ? JSON.parse(stickerData) : null,
      parseFloat(positionX),
      parseFloat(positionY),
      parseFloat(scale),
      parseFloat(rotation),
      metadata ? JSON.parse(metadata) : null
    ]);

    const layer = result.rows[0];

    // Publish to Kafka for real-time updates
    await producer.send({
      topic: 'remix-updates',
      messages: [{
        key: post.group_id,
        value: JSON.stringify({
          type: 'new_layer',
          groupId: post.group_id,
          postId,
          layer,
          addedBy: userId
        })
      }]
    });

    res.status(201).json({
      message: "Layer added successfully",
      layer,
    });

    console.log(`✅ Added ${layerType} layer to post ${postId}`);

  } catch (error) {
    console.error("Error adding layer:", error);
    res.status(500).json({ message: "Failed to add layer" });
  }
});

// GET /remixes/layers/:postId - Get all layers for a post
router.get("/layers/:postId", authenticateToken, async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;

  try {
    // Verify user has access to this post
    const accessCheck = await db.query(`
      SELECT 1 FROM remix_posts rp
      INNER JOIN remix_group_members rgm
        ON rp.group_id = rgm.group_id AND rgm.user_id = $1
      WHERE rp.id = $2
    `, [userId, postId]);

    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not authorized" });
    }

    // Get layers with user info
    const result = await db.query(`
      SELECT
        rl.*,
        u.first_name,
        u.last_name,
        u.username
      FROM remix_layers rl
      INNER JOIN users u ON rl.added_by = u.id
      WHERE rl.post_id = $1
      ORDER BY rl.created_at ASC
    `, [postId]);

    res.json({ layers: result.rows });

  } catch (error) {
    console.error("Error fetching layers:", error);
    res.status(500).json({ message: "Failed to fetch layers" });
  }
});

// DELETE /remixes/layers/:layerId - Delete a layer (only creator can delete)
router.delete("/layers/:layerId", authenticateToken, async (req, res) => {
  const { layerId } = req.params;
  const userId = req.user.userId;

  try {
    // Verify user owns this layer
    const result = await db.query(`
      DELETE FROM remix_layers
      WHERE id = $1 AND added_by = $2
      RETURNING post_id, layer_type, content_url
    `, [layerId, userId]);

    if (result.rows.length === 0) {
      return res.status(403).json({ message: "Not authorized" });
    }

    const { post_id, layer_type, content_url } = result.rows[0];

    // Delete image if it's a photo layer
    if (layer_type === 'photo' && content_url) {
      const imageId = content_url.split('/').pop().split('_')[0];
      await imageStorage.deleteImage(imageId);
    }

    // Get group ID for Kafka notification
    const postResult = await db.query(`
      SELECT group_id FROM remix_posts WHERE id = $1
    `, [post_id]);

    if (postResult.rows.length > 0) {
      await producer.send({
        topic: 'remix-updates',
        messages: [{
          key: postResult.rows[0].group_id,
          value: JSON.stringify({
            type: 'layer_deleted',
            groupId: postResult.rows[0].group_id,
            postId: post_id,
            layerId,
          })
        }]
      });
    }

    res.json({ message: "Layer deleted successfully" });

  } catch (error) {
    console.error("Error deleting layer:", error);
    res.status(500).json({ message: "Failed to delete layer" });
  }
});

module.exports = router;
