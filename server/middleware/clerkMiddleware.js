require("dotenv").config();
const { clerkClient } = require("@clerk/express");
const db = require("../db");
const winston = require("winston");

// Structured logging using Winston
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "logs/clerk.log" }),
  ],
});

/**
 * Middleware to authenticate Clerk JWT tokens
 * Verifies the token with Clerk and fetches the user from PostgreSQL
 */
exports.authenticateClerkToken = async (req, res, next) => {
  try {
    // Extract token from Authorization header or cookies
    const token = req.cookies?.access_token || req.header("Authorization")?.split(" ")[1];

    if (!token) {
      return res.status(403).json({ message: "Unauthorized - No token provided" });
    }

    // Verify token with Clerk
    let sessionClaims;
    try {
      // Use Clerk SDK to verify the session token
      const { data: session } = await clerkClient.sessions.verifyToken(token, {
        secretKey: process.env.CLERK_SECRET_KEY,
      });
      sessionClaims = session;
    } catch (verifyError) {
      logger.error("Clerk token verification failed:", verifyError);
      return res.status(403).json({ message: "Invalid or expired token" });
    }

    // Extract user ID from session
    const clerkUserId = sessionClaims.sub || sessionClaims.userId;

    if (!clerkUserId) {
      return res.status(403).json({ message: "Invalid token - missing user ID" });
    }

    // Fetch user from PostgreSQL database using clerk_user_id
    const userResult = await db.query(
      "SELECT id, username, email, first_name, last_name, clerk_user_id FROM users WHERE clerk_user_id = $1",
      [clerkUserId]
    );

    if (userResult.rows.length === 0) {
      logger.warn(`User not found in database for Clerk ID: ${clerkUserId}`);
      return res.status(404).json({ message: "User not found in database" });
    }

    const user = userResult.rows[0];

    // Attach user info and session to request object
    req.user = {
      id: user.id,
      username: user.username,
      email: user.email,
      firstName: user.first_name,
      lastName: user.last_name,
      clerkUserId: user.clerk_user_id,
    };
    req.clerkSessionId = sessionClaims.sid || sessionClaims.sessionId;

    logger.info(`User authenticated: ${user.email} (${user.id})`);
    next();
  } catch (error) {
    logger.error("Error in authenticateClerkToken middleware:", error);
    res.status(500).json({ message: "Authentication error" });
  }
};

/**
 * Middleware to enforce single-device session policy
 * Revokes old sessions when a new device logs in
 */
exports.enforceSingleSession = async (req, res, next) => {
  try {
    const userId = req.user?.id;
    const clerkSessionId = req.clerkSessionId;

    if (!userId || !clerkSessionId) {
      return res.status(403).json({ message: "User or session information missing" });
    }

    // Extract device and network information from request
    const userAgent = req.headers["user-agent"] || "Unknown";
    const ipAddress = req.ip || req.connection.remoteAddress || "Unknown";

    // Parse device type from user agent
    let deviceType = "desktop";
    let deviceName = "Unknown";

    if (userAgent.includes("Mobile") || userAgent.includes("Android")) {
      deviceType = "mobile";
    } else if (userAgent.includes("Tablet") || userAgent.includes("iPad")) {
      deviceType = "tablet";
    }

    // Simple device name extraction
    if (userAgent.includes("iPhone")) {
      deviceName = "iPhone";
    } else if (userAgent.includes("iPad")) {
      deviceName = "iPad";
    } else if (userAgent.includes("Android")) {
      deviceName = "Android Device";
    } else if (userAgent.includes("Macintosh")) {
      deviceName = "Mac";
    } else if (userAgent.includes("Windows")) {
      deviceName = "Windows PC";
    } else if (userAgent.includes("Linux")) {
      deviceName = "Linux";
    }

    // Check if this session already exists and is active
    const existingSession = await db.query(
      "SELECT id FROM user_sessions WHERE clerk_session_id = $1 AND is_active = true",
      [clerkSessionId]
    );

    if (existingSession.rows.length > 0) {
      // Update last_active timestamp for existing session
      await db.query(
        "UPDATE user_sessions SET last_active = NOW() WHERE clerk_session_id = $1",
        [clerkSessionId]
      );

      logger.info(`Session updated for user ${userId}`);
      return next();
    }

    // New session detected - revoke all other active sessions for this user
    const revokedSessions = await db.query(
      `UPDATE user_sessions
       SET is_active = false, revoked_at = NOW()
       WHERE user_id = $1 AND is_active = true
       RETURNING clerk_session_id`,
      [userId]
    );

    if (revokedSessions.rows.length > 0) {
      logger.info(`Revoked ${revokedSessions.rows.length} active session(s) for user ${userId}`);

      // Optionally: Revoke sessions with Clerk API
      for (const session of revokedSessions.rows) {
        try {
          await clerkClient.sessions.revokeSession(session.clerk_session_id);
        } catch (revokeError) {
          logger.warn(`Failed to revoke Clerk session ${session.clerk_session_id}:`, revokeError.message);
        }
      }
    }

    // Create new session record
    await db.query(
      `INSERT INTO user_sessions
       (user_id, clerk_session_id, device_type, device_name, user_agent, ip_address, is_active, last_active)
       VALUES ($1, $2, $3, $4, $5, $6, true, NOW())`,
      [userId, clerkSessionId, deviceType, deviceName, userAgent, ipAddress]
    );

    logger.info(`New session created for user ${userId} on ${deviceType} (${deviceName})`);
    next();
  } catch (error) {
    logger.error("Error in enforceSingleSession middleware:", error);

    // Don't block the request on session enforcement errors
    // Log the error but allow the request to proceed
    next();
  }
};

/**
 * Helper function to manually revoke a session
 * Can be called from logout endpoints
 */
exports.revokeSession = async (clerkSessionId) => {
  try {
    // Mark session as inactive in database
    await db.query(
      "UPDATE user_sessions SET is_active = false, revoked_at = NOW() WHERE clerk_session_id = $1",
      [clerkSessionId]
    );

    // Revoke session with Clerk
    await clerkClient.sessions.revokeSession(clerkSessionId);

    logger.info(`Session ${clerkSessionId} revoked successfully`);
    return true;
  } catch (error) {
    logger.error(`Error revoking session ${clerkSessionId}:`, error);
    return false;
  }
};

/**
 * Helper function to get all active sessions for a user
 */
exports.getUserActiveSessions = async (userId) => {
  try {
    const result = await db.query(
      `SELECT id, clerk_session_id, device_type, device_name, ip_address,
              created_at, last_active, is_active
       FROM user_sessions
       WHERE user_id = $1 AND is_active = true
       ORDER BY last_active DESC`,
      [userId]
    );

    return result.rows;
  } catch (error) {
    logger.error(`Error fetching active sessions for user ${userId}:`, error);
    return [];
  }
};
