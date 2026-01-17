// remixes.js - Daily Remix API routes
require("dotenv").config();
const express = require("express");
const router = express.Router();
const db = require("../db");
const { authenticateToken } = require("../middleware/authMiddleware");
const multer = require('multer');
const imageStorage = require('../services/imageStorage');
const { producer } = require('../kafkaClient');
const sharp = require('sharp');
const fs = require('fs').promises;
const path = require('path');
const turnService = require('../services/turnService');

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

  // Limit group size (2-5 members including creator)
  if (memberIds.length > 4 || memberIds.length < 1) {
    return res.status(400).json({ message: "Groups must have 2-5 members" });
  }

  try {
    // Create group
    const groupResult = await db.query(`
      INSERT INTO remix_groups (group_name, created_by)
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

    // Initialize turn order for the post
    await turnService.initializeTurnOrder(post.id, groupId);

    // Get updated post with turn information
    const updatedPostResult = await db.query(`
      SELECT rp.*, u.first_name, u.last_name
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
      WHERE rp.id = $1
    `, [post.id]);

    const updatedPost = updatedPostResult.rows[0];

    // Publish to Kafka for real-time updates
    await producer.send({
      topic: 'remix-updates',
      messages: [{
        key: groupId,
        value: JSON.stringify({
          type: 'new_post',
          groupId,
          post: updatedPost,
          postedBy: userId
        })
      }]
    });

    res.status(201).json({
      message: "Post created successfully",
      post: updatedPost,
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

    // Get today's post with all turn information
    const result = await db.query(`
      SELECT
        rp.*,
        u.first_name,
        u.last_name,
        cu.first_name as current_turn_first_name,
        cu.last_name as current_turn_last_name,
        cu.username as current_turn_username
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
      LEFT JOIN users cu ON rp.current_turn_user_id = cu.id
      WHERE rp.group_id = $1 AND rp.post_date = $2
    `, [groupId, today]);

    if (result.rows.length === 0) {
      return res.json({ post: null });
    }

    const post = result.rows[0];

    // Check if it's the current user's turn
    const turnCheck = await turnService.isUserTurn(post.id, userId);

    res.json({
      post,
      isMyTurn: turnCheck.isMyTurn
    });

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
        u.last_name
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
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


// GET /remixes/posts/:postId/turn-status - Get turn status for a post
router.get("/posts/:postId/turn-status", authenticateToken, async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId;

  try {
    // Get post to verify group membership
    const postResult = await db.query(`
      SELECT group_id FROM remix_posts WHERE id = $1
    `, [postId]);

    if (postResult.rows.length === 0) {
      return res.status(404).json({ message: "Post not found" });
    }

    const groupId = postResult.rows[0].group_id;

    // Verify user is in the group
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    // Get turn status
    const turnStatus = await turnService.getTurnStatus(postId);
    const turnCheck = await turnService.isUserTurn(postId, userId);

    res.json({
      ...turnStatus,
      isMyTurn: turnCheck.isMyTurn
    });

  } catch (error) {
    console.error("Error fetching turn status:", error);
    res.status(500).json({ message: "Failed to fetch turn status" });
  }
});

// ============================================
// LAYERS
// ============================================

// POST /remixes/layers - Add a photo layer to a post, merging it into the base image
router.post("/layers", authenticateToken, upload.single('image'), async (req, res) => {
  const { postId, positionX, positionY, scale, rotation } = req.body;
  const userId = req.user.userId;

  if (!req.file) {
    return res.status(400).json({ message: "Overlay image required" });
  }
  if (!postId || positionX == null || positionY == null || scale == null || rotation == null) {
    return res.status(400).json({ message: "Missing required layer parameters" });
  }

  try {
    // 1. Fetch the RemixPost (base image)
    const postResult = await db.query(`
      SELECT rp.*, rg.id as group_id
      FROM remix_posts rp
      JOIN remix_groups rg ON rp.group_id = rg.id
      WHERE rp.id = $1
    `, [postId]);

    if (postResult.rows.length === 0) {
      return res.status(404).json({ message: "Remix post not found" });
    }
    const post = postResult.rows[0];
    const groupId = post.group_id;

    // 2. Verify user is in the group of the post
    const memberCheck = await db.query(`
      SELECT 1 FROM remix_group_members
      WHERE group_id = $1 AND user_id = $2
    `, [groupId, userId]);

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Not a member of this group" });
    }

    // 2.5. Check if it's this user's turn
    const turnCheck = await turnService.isUserTurn(postId, userId);
    if (!turnCheck.isMyTurn) {
      return res.status(403).json({
        message: turnCheck.reason,
        currentTurnUserId: turnCheck.currentTurnUserId
      });
    }

    // 3. Read the current base image directly from disk
    const imageFilename = post.image_url.split('/').pop(); // Extract filename from URL
    const baseImagePath = path.join(__dirname, '../uploads/remixes', imageFilename);

    let baseImageBuffer;
    try {
      baseImageBuffer = await fs.readFile(baseImagePath);
    } catch (error) {
      console.error('Failed to read base image from disk:', error);
      return res.status(500).json({ message: 'Failed to read base image' });
    }

    // Get metadata from base image
    const baseImageMetadata = await sharp(baseImageBuffer).metadata();

    // 4. Process the overlay image with sharp
    const overlayImage = sharp(req.file.buffer);
    const overlayMetadata = await overlayImage.metadata();

    const baseWidth = baseImageMetadata.width;
    const baseHeight = baseImageMetadata.height;

    console.log('Base image dimensions:', baseWidth, 'x', baseHeight);
    console.log('Overlay original dimensions:', overlayMetadata.width, 'x', overlayMetadata.height);
    console.log('Position (normalized):', positionX, positionY);
    console.log('Scale:', scale, 'Rotation:', rotation);

    // Convert normalized client coordinates (0-1) to pixel coordinates
    const pixelCenterX = parseFloat(positionX) * baseWidth;
    const pixelCenterY = parseFloat(positionY) * baseHeight;

    // Calculate dimensions of the overlay after client-side scaling
    // Client scale is relative to the *original* overlay image dimensions
    const clientScaledOverlayWidth = overlayMetadata.width * parseFloat(scale);
    const clientScaledOverlayHeight = overlayMetadata.height * parseFloat(scale);

    console.log('Scaled overlay dimensions:', Math.round(clientScaledOverlayWidth), 'x', Math.round(clientScaledOverlayHeight));

    // Resize and rotate the overlay
    const processedOverlayBuffer = await sharp(req.file.buffer)
      .resize({
        width: Math.round(clientScaledOverlayWidth),
        height: Math.round(clientScaledOverlayHeight),
        fit: sharp.fit.contain,
        background: { r: 0, g: 0, b: 0, alpha: 0 }
      })
      .rotate(parseFloat(rotation), { background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png() // Convert to PNG to preserve transparency
      .toBuffer();

    // Get metadata of the processed overlay (after resize and rotate)
    const processedOverlayMetadata = await sharp(processedOverlayBuffer).metadata();

    // Calculate top-left for composite operation
    const compositeLeft = Math.round(pixelCenterX - (processedOverlayMetadata.width / 2));
    const compositeTop = Math.round(pixelCenterY - (processedOverlayMetadata.height / 2));

    console.log('Composite position (top-left):', compositeLeft, compositeTop);
    console.log('Processed overlay dimensions:', processedOverlayMetadata.width, 'x', processedOverlayMetadata.height);

    // 5. Composite the overlay onto the base image
    const mergedImageBuffer = await sharp(baseImageBuffer)
      .composite([{
        input: processedOverlayBuffer,
        left: compositeLeft,
        top: compositeTop,
        blend: 'over'
      }])
      .jpeg({ quality: 95 }) // Ensure high quality output
      .toBuffer();

    // 6. Upload the new merged image
    const imageData = await imageStorage.uploadImage(mergedImageBuffer);

    // 6.5. Delete the old image files to prevent storage bloat
    const oldImageFilename = post.image_url.split('/').pop();
    const oldImageId = oldImageFilename.split('_')[0]; // Extract UUID from filename
    imageStorage.deleteImage(oldImageId).catch(err => {
      console.warn('Failed to delete old image:', err);
      // Don't throw - cleanup failure shouldn't block the request
    });

    // 7. Update the RemixPost with the new image URL
    const updatedPostResult = await db.query(`
      UPDATE remix_posts
      SET image_url = $1, thumbnail_url = $2,
          image_width = $3, image_height = $4,
          updated_at = NOW()
      WHERE id = $5
      RETURNING *
    `, [
      imageData.originalUrl,
      imageData.thumbnailUrl,
      imageData.width,
      imageData.height,
      postId
    ]);

    const updatedPost = updatedPostResult.rows[0];

    // 8. Advance to next turn
    const turnResult = await turnService.advanceTurn(postId, userId);

    // Get final post with updated turn information
    const finalPostResult = await db.query(`
      SELECT rp.*, u.first_name, u.last_name
      FROM remix_posts rp
      LEFT JOIN users u ON rp.posted_by = u.id
      WHERE rp.id = $1
    `, [postId]);

    const finalPost = finalPostResult.rows[0];

    // 9. Publish to Kafka for real-time updates
    await producer.send({
      topic: 'remix-updates',
      messages: [{
        key: groupId,
        value: JSON.stringify({
          type: 'layer_added',
          groupId,
          postId: postId,
          post: finalPost,
          addedBy: userId,
          turnStatus: turnResult
        })
      }]
    });

    res.status(201).json({
      message: "Layer added and merged successfully",
      post: finalPost,
      turnStatus: turnResult,
    });

    console.log(`✅ Added layer to remix post ${postId} by user ${userId}`);

  } catch (error) {
    console.error("Error adding remix layer:", error);
    res.status(500).json({ message: "Failed to add layer" });
  }
});

// GET /remixes/layers/:postId - Get all layers for a post (deprecated, returns empty as layers are merged)
router.get("/layers/:postId", authenticateToken, async (req, res) => {
  const { postId } = req.params;
  const userId = req.user.userId; // Not directly used, but good to have context

  try {
    // For now, as layers are immediately merged into the main post image,
    // we return an empty array to indicate no distinct layers are stored separately.
    // In a more complex system, this might return historical layer data if stored.
    res.json({ layers: [] });
  } catch (error) {
    console.error("Error fetching remix layers (deprecated route):", error);
    res.status(500).json({ message: "Failed to fetch layers" });
  }
});

module.exports = router;
