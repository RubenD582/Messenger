const crypto = require("crypto");
require("dotenv").config();
const express = require("express");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcrypt");
const db = require("../db");
const fs = require("fs");
const path = require("path");
const rateLimit = require("express-rate-limit");
const Joi = require('joi');
const redisClient = require("../config/redisClient"); // Import the shared Redis client
const cors = require("cors");
const winston = require("winston");
const router = express.Router(); // Re-adding the router definition
const { authenticateToken } = require("../middleware/authMiddleware");

// Load private and public keys for JWT signing and verification
const privateKey = fs.readFileSync(path.join(__dirname, "../../config/keys/private_key.pem"), "utf8");
const publicKey = fs.readFileSync(path.join(__dirname, "../../config/keys/public_key.pem"), "utf8");

// Password schema validation (minimum 8 characters)
const passwordSchema = Joi.string().min(8).required().messages({
  'string.base': '"Password" should be a type of text',
  'string.min': '"Password" should have a minimum length of {#limit} characters',
  'string.empty': '"Password" cannot be empty',
  'any.required': '"Password" is required',
});

// Rate limiter to prevent brute force attacks (5 requests per 15 minutes)
const loginRegisterLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 5,
  message: "Too many requests from this IP, please try again after 1 minute.",
});

// Structured logging using Winston
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "logs/combined.log" }),
  ],
});

// Basic Route
router.get("/", (req, res) => {
  res.send("Server is running...");
});

// ===========================================
// OTP-BASED AUTHENTICATION ENDPOINTS
// ===========================================

const otpService = require("../services/otpService");
const emailService = require("../services/emailService");
const SecurityService = require("../services/securityService");

/**
 * POST /auth/register-with-email
 * Register a new user with email and send OTP for verification
 */
router.post("/register-with-email", loginRegisterLimiter, async (req, res) => {
  const { email, password, firstName, lastName } = req.body;

  try {
    // Validate input
    if (!email || !password || !firstName || !lastName) {
      return res.status(400).json({ message: "All fields are required" });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ message: "Invalid email format" });
    }

    // Validate password
    const { error: passwordError } = passwordSchema.validate(password);
    if (passwordError) {
      return res.status(400).json({ message: passwordError.details[0].message });
    }

    // Check if email already exists
    const existingUser = await db.query("SELECT * FROM users WHERE email = $1", [email]);
    if (existingUser.rows.length > 0) {
      return res.status(400).json({ message: "Email already registered" });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 12);

    // Generate OTP
    const otp = otpService.generateOTP();

    // Store OTP in Redis
    const storeResult = await otpService.storeOTP(email, otp, 'registration');
    if (!storeResult.success) {
      return res.status(429).json({ message: storeResult.error });
    }

    // Send OTP via email
    const emailResult = await emailService.sendOTP(email, otp, 'registration');
    if (!emailResult.success) {
      return res.status(500).json({ message: "Failed to send verification email" });
    }

    // Store user data temporarily in Redis (with OTP) for 10 minutes
    // This prevents creating unverified users in the database
    const tempUserData = {
      email,
      password: hashedPassword,
      firstName,
      lastName,
    };
    await redisClient.set(
      `temp:user:${email}`,
      JSON.stringify(tempUserData),
      'EX',
      10 * 60 // 10 minutes
    );

    logger.info(`Registration OTP sent to: ${email}`);

    res.status(200).json({
      success: true,
      message: "Verification code sent to your email",
      email: email,
      devMode: emailResult.devMode || false,
    });
  } catch (error) {
    logger.error("Error in /auth/register-with-email:", error);
    res.status(500).json({ message: "Registration failed" });
  }
});

/**
 * POST /auth/verify-email
 * Verify email with OTP and create user account
 */
router.post("/verify-email", async (req, res) => {
  const { email, otp } = req.body;

  try {
    // Validate input
    if (!email || !otp) {
      return res.status(400).json({ message: "Email and verification code are required" });
    }

    // Verify OTP
    const verifyResult = await otpService.verifyOTP(email, otp, 'registration');
    if (!verifyResult.success) {
      return res.status(400).json({ message: verifyResult.error });
    }

    // Get temporary user data from Redis
    const tempUserDataJson = await redisClient.get(`temp:user:${email}`);
    if (!tempUserDataJson) {
      return res.status(400).json({ message: "Registration session expired. Please register again." });
    }

    const tempUserData = JSON.parse(tempUserDataJson);

    // Create user in database
    const result = await db.query(
      "INSERT INTO users (email, password, first_name, last_name, email_verified) VALUES ($1, $2, $3, $4, $5) RETURNING id, email, first_name, last_name",
      [tempUserData.email, tempUserData.password, tempUserData.firstName, tempUserData.lastName, true]
    );

    const user = result.rows[0];

    // Delete temporary user data from Redis
    await redisClient.del(`temp:user:${email}`);

    // Generate JWT token
    const token = jwt.sign(
      { email: user.email, userId: user.id },
      privateKey,
      { algorithm: "RS256", expiresIn: "1h" }
    );

    // Store JWT in HttpOnly cookie
    res.cookie("access_token", token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "Strict",
    });

    logger.info(`Email verified and user created: ${email}`);

    res.status(201).json({
      success: true,
      message: "Email verified successfully",
      user: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
      },
      token: token,
    });
  } catch (error) {
    logger.error("Error in /auth/verify-email:", error);
    res.status(500).json({ message: "Email verification failed" });
  }
});

/**
 * POST /auth/login-with-email
 * Login with email/password and optionally send OTP for 2FA
 * Now with: Instagram-style lockout, single device sessions, IP tracking
 */
router.post("/login-with-email", loginRegisterLimiter, async (req, res) => {
  const { email, password, use2FA } = req.body;
  const ipAddress = req.ip || req.connection.remoteAddress;
  const userAgent = req.get('user-agent') || 'unknown';

  try {
    // Validate input
    if (!email || !password) {
      return res.status(400).json({ message: "Email and password are required" });
    }

    // CHECK 1: Instagram-style lockout check
    const lockout = await SecurityService.checkLoginLockout(email);
    if (lockout.locked) {
      const minutes = Math.ceil(lockout.waitSeconds / 60);
      return res.status(429).json({
        message: `Too many failed attempts. Please wait ${minutes} minute${minutes > 1 ? 's' : ''} before trying again.`,
        waitSeconds: lockout.waitSeconds
      });
    }

    // Check if user exists
    const result = await db.query("SELECT * FROM users WHERE email = $1", [email]);
    if (result.rows.length === 0) {
      // Track failed attempt
      await SecurityService.trackFailedLogin(email);
      return res.status(400).json({ message: "Invalid email or password" });
    }

    const user = result.rows[0];

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      // Track failed attempt with progressive delays
      const failInfo = await SecurityService.trackFailedLogin(email);

      let message = "Invalid email or password";
      if (failInfo.delaySeconds > 0) {
        const minutes = Math.ceil(failInfo.delaySeconds / 60);
        message = `Invalid email or password. Please wait ${minutes} minute${minutes > 1 ? 's' : ''} before trying again.`;
      }

      return res.status(400).json({ message });
    }

    // SUCCESS: Clear failed login attempts
    await SecurityService.clearFailedLogins(email);

    // Check if email is verified
    if (!user.email_verified) {
      return res.status(403).json({ message: "Please verify your email before logging in" });
    }

    // If 2FA is requested, send OTP
    if (use2FA) {
      const otp = otpService.generateOTP();
      const storeResult = await otpService.storeOTP(email, otp, '2fa');

      if (!storeResult.success) {
        return res.status(429).json({ message: storeResult.error });
      }

      const emailResult = await emailService.sendOTP(email, otp, '2fa');
      if (!emailResult.success) {
        return res.status(500).json({ message: "Failed to send 2FA code" });
      }

      return res.status(200).json({
        success: true,
        requires2FA: true,
        message: "2FA code sent to your email",
        email: email,
      });
    }

    // CHECK 2: Generate refresh token + short-lived access token
    const { accessToken, refreshToken } = SecurityService.generateTokens(user);

    // CHECK 3: Create single device session (invalidates other devices)
    await SecurityService.createSession(user.id, refreshToken, ipAddress, userAgent);

    // Store refresh token
    await SecurityService.storeRefreshToken(user.id, refreshToken);

    // Store JWT in HttpOnly cookie
    res.cookie("access_token", accessToken, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "Strict",
    });

    // Update last_login timestamp
    await db.query("UPDATE users SET last_login = NOW() WHERE id = $1", [user.id]);

    logger.info(`User logged in: ${email} from IP: ${ipAddress}`);

    res.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        firstName: user.first_name,
        lastName: user.last_name,
      },
      accessToken: accessToken,
      refreshToken: refreshToken,
    });
  } catch (error) {
    logger.error("Error in /auth/login-with-email:", error);
    res.status(500).json({ message: "Login failed" });
  }
});

/**
 * POST /auth/refresh-token
 * Exchange refresh token for new access token
 */
router.post("/refresh-token", async (req, res) => {
  const { refreshToken } = req.body;
  const ipAddress = req.ip || req.connection.remoteAddress;

  try {
    if (!refreshToken) {
      return res.status(400).json({ message: "Refresh token required" });
    }

    // Verify refresh token is not blacklisted
    const tokenCheck = await SecurityService.verifyRefreshToken(refreshToken);
    if (!tokenCheck.valid) {
      return res.status(403).json({ message: tokenCheck.reason });
    }

    // Verify JWT signature
    const decoded = jwt.verify(refreshToken, publicKey, { algorithms: ["RS256"] });

    if (decoded.type !== 'refresh') {
      return res.status(403).json({ message: "Invalid token type" });
    }

    // Get active session
    const session = await SecurityService.getActiveSession(decoded.userId);
    if (!session || session.refreshToken !== refreshToken) {
      return res.status(403).json({ message: "Session expired or invalid" });
    }

    // CHECK: IP switching detection
    const ipCheck = await SecurityService.checkIPSwitch(decoded.userId, ipAddress, session.ipAddress);
    if (ipCheck.suspicious) {
      logger.warn(`Suspicious IP switching detected for user ${decoded.userId}: ${ipCheck.switchCount} switches`);
      // Could optionally require re-authentication here
      // return res.status(403).json({ message: "Suspicious activity detected. Please log in again." });
    }

    // Get user data
    const userResult = await db.query("SELECT * FROM users WHERE id = $1", [decoded.userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const user = userResult.rows[0];

    // ROTATE: Generate new tokens
    const newTokens = SecurityService.generateTokens(user);

    // Blacklist old refresh token
    await redisClient.set(`blacklist:${refreshToken}`, '1', 'EX', 7 * 24 * 60 * 60);

    // Update session with new refresh token
    await SecurityService.createSession(
      user.id,
      newTokens.refreshToken,
      ipAddress,
      session.userAgent
    );

    // Store new refresh token
    await SecurityService.storeRefreshToken(user.id, newTokens.refreshToken);

    logger.info(`Token refreshed for user: ${user.email}`);

    res.json({
      success: true,
      accessToken: newTokens.accessToken,
      refreshToken: newTokens.refreshToken,
    });

  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(403).json({ message: "Refresh token expired. Please log in again." });
    }
    logger.error("Error refreshing token:", error);
    res.status(403).json({ message: "Invalid refresh token" });
  }
});

/**
 * POST /auth/verify-2fa
 * Verify 2FA code and issue JWT token
 */
router.post("/verify-2fa", async (req, res) => {
  const { email, otp } = req.body;

  try {
    // Validate input
    if (!email || !otp) {
      return res.status(400).json({ message: "Email and 2FA code are required" });
    }

    // Verify OTP
    const verifyResult = await otpService.verifyOTP(email, otp, '2fa');
    if (!verifyResult.success) {
      return res.status(400).json({ message: verifyResult.error });
    }

    // Get user from database
    const result = await db.query("SELECT * FROM users WHERE email = $1", [email]);
    if (result.rows.length === 0) {
      return res.status(400).json({ message: "User not found" });
    }

    const user = result.rows[0];

    // Generate JWT token
    const token = jwt.sign(
      { email: user.email, userId: user.id },
      privateKey,
      { algorithm: "RS256", expiresIn: "1h" }
    );

    // Store JWT in HttpOnly cookie
    res.cookie("access_token", token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "Strict",
    });

    // Update last_login timestamp
    await db.query("UPDATE users SET last_login = NOW() WHERE id = $1", [user.id]);

    logger.info(`2FA verified and user logged in: ${email}`);

    res.json({
      success: true,
      message: "2FA verified successfully",
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        firstName: user.first_name,
        lastName: user.last_name,
      },
      token: token,
    });
  } catch (error) {
    logger.error("Error in /auth/verify-2fa:", error);
    res.status(500).json({ message: "2FA verification failed" });
  }
});

/**
 * GET /auth/me
 * Get current authenticated user info
 * Protected by JWT authentication middleware
 */
router.get("/me", authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      "SELECT id, email, username, first_name, last_name, email_verified, last_login FROM users WHERE id = $1",
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const user = result.rows[0];

    res.json({
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        firstName: user.first_name,
        lastName: user.last_name,
        emailVerified: user.email_verified,
        lastLogin: user.last_login,
      },
      authenticated: true,
    });
  } catch (error) {
    logger.error("Error in /auth/me endpoint:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Export the router
module.exports = router;

/**
 * POST /auth/forgot-password
 * Request a password reset email
 */
router.post("/forgot-password", async (req, res) => {
  const { email } = req.body;

  try {
    // Validate input
    if (!email) {
      return res.status(400).json({ message: "Email is required" });
    }

    // Check if email exists
    const userResult = await db.query("SELECT id, email FROM users WHERE email = $1", [email]);
    if (userResult.rows.length === 0) {
      // For security, send a generic success message even if email not found
      // to prevent email enumeration
      return res.status(200).json({ success: true, message: "If your email is registered, you will receive a password reset link." });
    }

    const user = userResult.rows[0];

    // Generate a secure, URL-safe reset token
    const resetToken = crypto.randomBytes(32).toString('hex');

    // Store the reset token in Redis with a 1-hour expiry
    // Key: passwordReset:${token}, Value: userId
    await redisClient.set(`passwordReset:${resetToken}`, user.id.toString(), 'EX', 3600); // 1 hour expiry

    // Send password reset email
    const emailResult = await emailService.sendPasswordReset(user.email, resetToken);

    if (!emailResult.success) {
      logger.error(`Failed to send password reset email to ${email}:`, emailResult.error);
      return res.status(500).json({ message: "Failed to send password reset email" });
    }

    logger.info(`Password reset link sent to: ${email}`);
    res.status(200).json({ success: true, message: "If your email is registered, you will receive a password reset link." });

  } catch (error) {
    logger.error("Error in /auth/forgot-password:", error);
    res.status(500).json({ message: "Server error during password reset request" });
  }
});

/**
 * POST /auth/reset-password
 * Reset user's password using a valid token
 */
router.post("/reset-password", async (req, res) => {
  const { token, newPassword } = req.body;

  try {
    // Validate input
    if (!token || !newPassword) {
      return res.status(400).json({ message: "Token and new password are required" });
    }

    // Validate new password
    const { error: passwordError } = passwordSchema.validate(newPassword);
    if (passwordError) {
      return res.status(400).json({ message: passwordError.details[0].message });
    }

    // Retrieve user ID from Redis using the token
    const userId = await redisClient.get(`passwordReset:${token}`);

    if (!userId) {
      return res.status(400).json({ message: "Password reset token is invalid or has expired." });
    }

    // Hash the new password
    const hashedPassword = await bcrypt.hash(newPassword, 12);

    // Update user's password in the database
    await db.query("UPDATE users SET password = $1 WHERE id = $2", [hashedPassword, userId]);

    // SECURITY: Revoke all tokens for this user (logout all devices)
    await SecurityService.revokeAllUserTokens(userId);

    // Delete the reset token from Redis to prevent reuse
    await redisClient.del(`passwordReset:${token}`);

    logger.info(`Password reset for user ID: ${userId} - all sessions revoked`);
    res.status(200).json({
      success: true,
      message: "Your password has been successfully reset. All devices have been logged out for security."
    });

  } catch (error) {
    logger.error("Error in /auth/reset-password:", error);
    res.status(500).json({ message: "Server error during password reset" });
  }
});

