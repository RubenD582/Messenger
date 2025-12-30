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


// Username schema validation (minimum 3 characters)
const usernameSchema = Joi.string().min(3).required().messages({
  'string.base': '"Username" should be a type of text',
  'string.min': '"Username" should have a minimum length of {#limit} characters',
  'string.empty': '"Username" cannot be empty',
  'any.required': '"Username" is required',
});

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

// Register Route
router.post("/register", loginRegisterLimiter, async (req, res) => {
  const { username, password, first_name, last_name } = req.body;

  // Validate username and password
  const { error: usernameError } = usernameSchema.validate(username);
  const { error: passwordError } = passwordSchema.validate(password);

  if (usernameError) {
    return res.status(400).json({ message: usernameError.details[0].message });
  }

  if (passwordError) {
    return res.status(400).json({ message: passwordError.details[0].message });
  }

  // Validate first and last name (simple length check for example)
  if (!first_name || first_name.trim().length === 0) {
    return res.status(400).json({ message: "First name is required" });
  }

  if (!last_name || last_name.trim().length === 0) {
    return res.status(400).json({ message: "Last name is required" });
  }

  try {
    // Check if the username already exists in the database
    const existingUser = await db.query("SELECT * FROM users WHERE username = $1", [username]);
    if (existingUser.rows.length > 0) {
      return res.status(400).json({ message: "Username already taken" });
    }

    // Hash the password with a higher salt rounds (12 rounds for stronger security)
    const hashedPassword = await bcrypt.hash(password, 12);

    // Insert the new user into the database
    const result = await db.query(
      "INSERT INTO users (username, password, first_name, last_name) VALUES ($1, $2, $3, $4) RETURNING id, username, first_name, last_name",
      [username, hashedPassword, first_name, last_name]
    );

    // Respond with success message
    res.status(201).json({
      message: "User registered successfully",
      username: result.rows[0].username,
      first_name: result.rows[0].first_name,
      last_name: result.rows[0].last_name
    });
  } catch (error) {
    logger.error("Error during registration:", error);
    res.status(500).json({ message: "Server error" });
  }
});


// Login Route
router.post("/login", loginRegisterLimiter, async (req, res) => {
  const { username, password } = req.body;

  try {
    // Check if the user exists in the database
    const result = await db.query("SELECT * FROM users WHERE username = $1", [username]);
    if (result.rows.length === 0) {
      return res.status(400).json({ message: "Invalid username or password" });
    }

    // Validate the password using bcrypt
    const user = result.rows[0];
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      return res.status(400).json({ message: "Invalid username or password" });
    }

    // Sign JWT using the private key (RS256)
    const token = jwt.sign({ username: user.username, userId: user.id }, privateKey, { algorithm: "RS256", expiresIn: "1h" });

    // Store JWT in an HttpOnly cookie for better security (prevents XSS)
    res.cookie("access_token", token, { 
      httpOnly: true, 
      secure: process.env.NODE_ENV === "production", 
      sameSite: "Strict" 
    });
    

    // Respond with the username
    res.json({ username: user.username, uuid: user.id });
  } catch (error) {
    logger.error("Error during login:", error);
    res.status(500).json({ message: "Server error" });
  }
});

// Refresh Token Route
router.post("/refresh-token", authenticateToken, async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken) {
    return res.status(403).json({ message: "No refresh token provided" });
  }

  try {
    // Verify the refresh token using the public key
    const decoded = jwt.verify(refreshToken, publicKey, { algorithms: ["RS256"] });

    // Check if the refresh token is blacklisted
    const reply = await redisClient.sIsMember("blacklisted_tokens", refreshToken);
    
    if (reply === 1) {
      return res.status(403).json({ message: "Refresh token is blacklisted" });
    }

    // Issue a new access token
    const newToken = jwt.sign(
      { username: decoded.username, userId: decoded.userId },
      privateKey,
      { algorithm: "RS256", expiresIn: "1h" }
    );

    res.json({ token: newToken });
  } catch (error) {
    logger.error("Error during refresh token:", error);
    res.status(403).json({ message: "Invalid refresh token" });
  }
});

router.post("/logout", authenticateToken, async (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ message: "No token provided" });
  }

  try {
    // Blacklist the token (Store it in Redis for distributed revocation)
    const reply = await redisClient.sAdd('blacklisted_tokens', token);

    if (reply === 0) {
      // The token already exists in the set
      return res.status(200).json({ message: "Token already blacklisted" });
    }
    res.json({ message: "Logged out successfully" });
  } catch (error) {
    logger.error("Error during logout:", error);
    res.status(500).json({ message: "Server error" });
  }
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
 */
router.post("/login-with-email", loginRegisterLimiter, async (req, res) => {
  const { email, password, use2FA } = req.body;

  try {
    // Validate input
    if (!email || !password) {
      return res.status(400).json({ message: "Email and password are required" });
    }

    // Check if user exists
    const result = await db.query("SELECT * FROM users WHERE email = $1", [email]);
    if (result.rows.length === 0) {
      return res.status(400).json({ message: "Invalid email or password" });
    }

    const user = result.rows[0];

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      return res.status(400).json({ message: "Invalid email or password" });
    }

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

    // No 2FA - issue token directly
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

    logger.info(`User logged in: ${email}`);

    res.json({
      success: true,
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
    logger.error("Error in /auth/login-with-email:", error);
    res.status(500).json({ message: "Login failed" });
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
