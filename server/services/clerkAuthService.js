require("dotenv").config();
const { createClerkClient } = require("@clerk/backend");
const winston = require("winston");

// Initialize Clerk client with secret key
const clerkClient = createClerkClient({
  secretKey: process.env.CLERK_SECRET_KEY
});

// Logger
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "logs/clerk-auth.log" }),
  ],
});

/**
 * Create a new user with email and password
 * This uses Clerk's Backend SDK to create users server-side
 * Note: Emails are automatically verified when created via Backend SDK
 */
async function createUser(email, password, firstName, lastName) {
  try {
    logger.info(`Creating user with email: ${email}`);

    // Create user with Clerk Backend SDK
    // Emails are automatically verified by default
    const user = await clerkClient.users.createUser({
      emailAddress: [email],
      password: password,
      firstName: firstName,
      lastName: lastName,
      skipPasswordRequirement: false,
      skipPasswordChecks: false,
    });

    logger.info(`User created successfully: ${user.id}`);

    return {
      success: true,
      userId: user.id,
      message: "User created successfully",
    };
  } catch (error) {
    logger.error("Error creating user:", error);

    // Handle specific Clerk errors
    const errorMessage = error.errors?.[0]?.message || error.message || "Failed to create user";

    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Verify email with OTP code
 */
async function verifyEmail(userId, code) {
  try {
    logger.info(`Verifying email for user: ${userId}`);

    // Get the user
    const user = await clerkClient.users.getUser(userId);
    const emailId = user.emailAddresses[0]?.id;

    if (!emailId) {
      return {
        success: false,
        error: "No email address found for user",
      };
    }

    // Attempt to verify the email with the code
    const result = await clerkClient.emailAddresses.attemptEmailAddressVerification({
      emailAddressId: emailId,
      code: code,
    });

    if (result.verification?.status === 'verified') {
      logger.info(`Email verified successfully for user: ${userId}`);
      return {
        success: true,
        message: "Email verified successfully",
      };
    }

    return {
      success: false,
      error: "Invalid verification code",
    };
  } catch (error) {
    logger.error("Error verifying email:", error);
    const errorMessage = error.errors?.[0]?.message || error.message || "Verification failed";
    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Get user by Clerk user ID
 */
async function getUserById(userId) {
  try {
    const user = await clerkClient.users.getUser(userId);
    return {
      success: true,
      user: {
        id: user.id,
        email: user.emailAddresses[0]?.emailAddress,
        firstName: user.firstName,
        lastName: user.lastName,
      },
    };
  } catch (error) {
    logger.error("Error getting user:", error);
    return {
      success: false,
      error: error.message || "Failed to get user",
    };
  }
}

module.exports = {
  createUser,
  verifyEmail,
  getUserById,
  clerkClient,
};
