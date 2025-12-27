require("dotenv").config();
const express = require("express");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcrypt");
const db = require("../db");
const fs = require("fs");
const path = require("path");
const rateLimit = require("express-rate-limit");
const Joi = require('joi');
const Redis = require('redis');
const cors = require("cors");
const winston = require("winston");
const router = express.Router();
const { authenticateToken } = require("../middleware/authMiddleware");

// Load private and public keys for JWT signing and verification
const privateKey = fs.readFileSync(path.join(__dirname, "../../config/keys/private_key.pem"), "utf8");
const publicKey = fs.readFileSync(path.join(__dirname, "../../config/keys/public_key.pem"), "utf8");

// Create Redis client for rate limiting and token blacklist
const redisClient = Redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6380,
  }
});

redisClient.connect();

// Handle connection errors
redisClient.on('error', (err) => {
  console.log('Redis error:', err);
});

// User schema validation with Joi (including alphanumeric + _ and .)
const usernameSchema = Joi.string()
  .pattern(/^[a-zA-Z0-9_.]+$/) // Allow alphanumeric, _ and .
  .min(3)
  .max(20)
  .required()
  .messages({
    'string.base': '"Username" should be a type of text',
    'string.pattern.base': '"Username" can only contain alphanumeric characters, underscores, and periods',
    'string.min': '"Username" should have a minimum length of {#limit} characters',
    'string.max': '"Username" should have a maximum length of {#limit} characters',
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
    redisClient.sIsMember("blacklisted_tokens", refreshToken, (err, reply) => {
      if (err) {
        logger.error("Redis error:", err);
        return res.status(500).json({ message: "Server error" });
      }

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
    });
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

// Export the router
module.exports = router;
