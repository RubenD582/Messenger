require("dotenv").config();
const express = require("express");
const { Webhook } = require("svix");
const db = require("../db");
const winston = require("winston");

const router = express.Router();

// Structured logging using Winston
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "logs/webhooks.log" }),
  ],
});

/**
 * Clerk Webhook Endpoint
 *
 * IMPORTANT: This route must be registered BEFORE body-parser middleware
 * because Svix signature verification requires the raw request body
 *
 * Handles the following events:
 * - user.created: Create new user in PostgreSQL
 * - user.updated: Update existing user in PostgreSQL
 * - user.deleted: Delete user from PostgreSQL (soft delete recommended)
 */
router.post("/clerk", express.raw({ type: "application/json" }), async (req, res) => {
  try {
    // Get Svix headers for webhook verification
    const svixId = req.headers["svix-id"];
    const svixTimestamp = req.headers["svix-timestamp"];
    const svixSignature = req.headers["svix-signature"];

    // Verify all required headers are present
    if (!svixId || !svixTimestamp || !svixSignature) {
      logger.warn("Missing Svix headers in webhook request");
      return res.status(400).json({ error: "Missing Svix headers" });
    }

    // Get the webhook secret from environment
    const webhookSecret = process.env.CLERK_WEBHOOK_SECRET;

    if (!webhookSecret) {
      logger.error("CLERK_WEBHOOK_SECRET not configured");
      return res.status(500).json({ error: "Webhook secret not configured" });
    }

    // Get the raw body (as string)
    const payload = req.body.toString();

    // Create Svix instance for verification
    const wh = new Webhook(webhookSecret);

    let evt;
    try {
      // Verify the webhook signature
      evt = wh.verify(payload, {
        "svix-id": svixId,
        "svix-timestamp": svixTimestamp,
        "svix-signature": svixSignature,
      });
    } catch (verifyError) {
      logger.error("Webhook signature verification failed:", verifyError.message);
      return res.status(400).json({ error: "Invalid webhook signature" });
    }

    // Parse the verified event
    const eventType = evt.type;
    const eventData = evt.data;

    logger.info(`Received Clerk webhook: ${eventType}`, { userId: eventData.id });

    // Handle different event types
    switch (eventType) {
      case "user.created":
        await handleUserCreated(eventData);
        break;

      case "user.updated":
        await handleUserUpdated(eventData);
        break;

      case "user.deleted":
        await handleUserDeleted(eventData);
        break;

      default:
        logger.warn(`Unhandled webhook event type: ${eventType}`);
    }

    // Respond with success
    res.status(200).json({ received: true });
  } catch (error) {
    logger.error("Error processing webhook:", error);
    res.status(500).json({ error: "Webhook processing failed" });
  }
});

/**
 * Handle user.created event
 * Creates a new user in PostgreSQL database
 */
async function handleUserCreated(userData) {
  try {
    const clerkUserId = userData.id;
    const email = userData.email_addresses?.[0]?.email_address;
    const firstName = userData.first_name || "";
    const lastName = userData.last_name || "";
    const username = userData.username || email?.split("@")[0] || `user_${clerkUserId.slice(0, 8)}`;

    // Check if user already exists (idempotency)
    const existingUser = await db.query(
      "SELECT id FROM users WHERE clerk_user_id = $1",
      [clerkUserId]
    );

    if (existingUser.rows.length > 0) {
      logger.info(`User already exists in database: ${clerkUserId}`);
      return;
    }

    // Insert new user into PostgreSQL
    const result = await db.query(
      `INSERT INTO users (clerk_user_id, email, username, first_name, last_name, verified)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, email, username`,
      [clerkUserId, email, username, firstName, lastName, true]
    );

    logger.info(`User created in database: ${result.rows[0].email} (ID: ${result.rows[0].id})`);
  } catch (error) {
    logger.error("Error handling user.created event:", error);
    throw error;
  }
}

/**
 * Handle user.updated event
 * Updates existing user in PostgreSQL database
 */
async function handleUserUpdated(userData) {
  try {
    const clerkUserId = userData.id;
    const email = userData.email_addresses?.[0]?.email_address;
    const firstName = userData.first_name || "";
    const lastName = userData.last_name || "";
    const username = userData.username || email?.split("@")[0];

    // Update user in PostgreSQL
    const result = await db.query(
      `UPDATE users
       SET email = $1, username = $2, first_name = $3, last_name = $4, updated_at = NOW()
       WHERE clerk_user_id = $5
       RETURNING id, email, username`,
      [email, username, firstName, lastName, clerkUserId]
    );

    if (result.rows.length === 0) {
      logger.warn(`User not found for update: ${clerkUserId}`);
      // User doesn't exist - create it (webhook event ordering issue)
      await handleUserCreated(userData);
      return;
    }

    logger.info(`User updated in database: ${result.rows[0].email} (ID: ${result.rows[0].id})`);
  } catch (error) {
    logger.error("Error handling user.updated event:", error);
    throw error;
  }
}

/**
 * Handle user.deleted event
 * Soft deletes user in PostgreSQL database (recommended)
 * Or hard deletes if preferred
 */
async function handleUserDeleted(userData) {
  try {
    const clerkUserId = userData.id;

    // Option 1: Soft delete (recommended) - add deleted_at column to users table
    // const result = await db.query(
    //   "UPDATE users SET deleted_at = NOW() WHERE clerk_user_id = $1 RETURNING id",
    //   [clerkUserId]
    // );

    // Option 2: Hard delete - permanently remove user
    // WARNING: This will cascade delete all user data (chats, friends, etc.)
    const result = await db.query(
      "DELETE FROM users WHERE clerk_user_id = $1 RETURNING id, email",
      [clerkUserId]
    );

    if (result.rows.length === 0) {
      logger.warn(`User not found for deletion: ${clerkUserId}`);
      return;
    }

    logger.info(`User deleted from database: ${result.rows[0].email} (ID: ${result.rows[0].id})`);

    // Also revoke all active sessions for this user
    await db.query(
      "UPDATE user_sessions SET is_active = false, revoked_at = NOW() WHERE user_id = $1",
      [result.rows[0].id]
    );

    logger.info(`All sessions revoked for deleted user ${result.rows[0].id}`);
  } catch (error) {
    logger.error("Error handling user.deleted event:", error);
    throw error;
  }
}

module.exports = router;
