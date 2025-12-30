// ============================================
// DEPRECATED - DO NOT USE
// ============================================
// This file is deprecated as of the latest refactor.
// Authentication is now handled directly from the Flutter client
// calling Clerk's Frontend API, not proxied through this backend.
//
// The backend only validates Clerk session tokens via:
// - GET /auth/me (validate session and get user info)
// - POST /auth/clerk-logout (revoke session)
//
// This file is kept for reference but should not be used.
// ============================================

require("dotenv").config();
const axios = require("axios");
const { CookieJar } = require("tough-cookie");
const { wrapper } = require("axios-cookiejar-support");

// --------------------
// Constants
// --------------------
const CLERK_FRONTEND_API = process.env.CLERK_FRONTEND_API; // Get from .env

// --------------------
// Logging
// --------------------
const winston = require("winston");
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "logs/clerk-service.log" }),
  ],
});

// --------------------
// Helper to create Clerk API client with cookie support
// --------------------
function createClerkApiClient() {
  const jar = new CookieJar();
  const client = wrapper(axios.create({
    baseURL: CLERK_FRONTEND_API,
    headers: {
      "Content-Type": "application/json",
    },
    jar,
    withCredentials: true,
  }));
  return client;
}

// --------------------
// Functions
// --------------------

async function signUpWithEmailPassword(email, password, firstName, lastName) {
  const client = createClerkApiClient();

  try {
    logger.info(`Starting sign-up flow for: ${email}`);

    // Step 1: Create a sign-up session using frontend API
    const signUpResponse = await client.post(
      `/v1/client/sign_ups`,
      {
        email_address: email,
        password: password,
        first_name: firstName,
        last_name: lastName,
      }
    );

    const signUpData = signUpResponse.data.response || signUpResponse.data;
    logger.info("Sign-up created:", { status: signUpData.status, id: signUpData.id });

    // Step 2: Prepare email verification
    await client.post(
      `/v1/client/sign_ups/${signUpData.id}/prepare_verification`,
      { strategy: "email_code" }
    );

    logger.info("Email verification prepared for:", email);

    return {
      success: false,
      requiresVerification: true,
      signUpId: signUpData.id,
      message: "Verification code sent to your email",
    };
  } catch (error) {
    logger.error("Error in signUpWithEmailPassword:", error);
    const errorMessage = error.response?.data?.errors?.[0]?.message || error.message;
    return { success: false, error: errorMessage || "Failed to create user." };
  }
}

async function signInWithEmailPassword(email, password) {
  const client = createClerkApiClient();

  try {
    logger.info(`Attempting sign-in with Clerk frontend API: ${email}`);

    // Step 1: Create sign-in with identifier
    const createResponse = await client.post(
      `/v1/client/sign_ins`,
      { identifier: email }
    );

    const signInData = createResponse.data.response || createResponse.data;
    logger.info("Sign-in created:", { status: signInData.status, id: signInData.id });

    // Step 2: Attempt password authentication
    const attemptResponse = await client.post(
      `/v1/client/sign_ins/${signInData.id}/attempt_first_factor`,
      { strategy: "password", password }
    );

    const attemptData = attemptResponse.data.response || attemptResponse.data;
    logger.info("Password attempt response:", { status: attemptData.status });

    // Check if email verification is needed after password
    if (attemptData.status === "needs_first_factor") {
      logger.info(`Email verification required for ${email}`);

      // Prepare email code verification
      await client.post(
        `/v1/client/sign_ins/${attemptData.id}/prepare_first_factor`,
        { strategy: "email_code" }
      );

      return {
        success: false,
        requires2FA: true,
        signInId: attemptData.id,
        message: "Verification code sent to your email",
      };
    }

    // Check if second factor is needed
    if (attemptData.status === "needs_second_factor") {
      logger.info(`2FA required for ${email}, sending email code...`);
      await client.post(
        `/v1/client/sign_ins/${attemptData.id}/prepare_second_factor`,
        { strategy: "email_code" }
      );

      return {
        success: false,
        requires2FA: true,
        signInId: attemptData.id,
        message: "2FA code sent to your email",
      };
    }

    if (attemptData.status === "complete") {
      logger.info(`Sign-in complete for ${email}`);
      return {
        success: true,
        requires2FA: false,
        sessionToken: attemptData.last_active_session_id,
      };
    }

    logger.warn(`Unexpected sign-in status: ${attemptData.status}`);
    return { success: false, error: `Sign-in incomplete. Please try again.` };
  } catch (error) {
    logger.error("Error in signInWithEmailPassword:", error);
    const errorMessage = error.response?.data?.errors?.[0]?.message || error.message;
    return { success: false, error: errorMessage || "Invalid credentials." };
  }
}

async function verifySignUpCode(signUpId, code) {
  const client = createClerkApiClient();

  try {
    logger.info(`Verifying sign-up code for signUpId: ${signUpId}`);

    const response = await client.post(
      `/v1/client/sign_ups/${signUpId}/attempt_verification`,
      { strategy: "email_code", code }
    );

    const signUpData = response.data.response || response.data;
    logger.info("Sign-up verification response:", { status: signUpData.status });

    if (signUpData.status === "complete") {
      logger.info(`Sign-up complete for signUpId ${signUpId}`);
      return { success: true, sessionToken: signUpData.created_session_id };
    }

    return { success: false, error: "Invalid verification code" };
  } catch (error) {
    logger.error("Error in verifySignUpCode:", error);
    const errorMessage = error.response?.data?.errors?.[0]?.message || error.message;
    return { success: false, error: errorMessage || "Invalid verification code." };
  }
}

async function verify2FACode(signInId, code) {
  const client = createClerkApiClient();

  try {
    logger.info(`Verifying 2FA code for signInId: ${signInId}`);

    // Try first factor verification first
    let response;
    try {
      response = await client.post(
        `/v1/client/sign_ins/${signInId}/attempt_first_factor`,
        { strategy: "email_code", code }
      );
    } catch (firstFactorError) {
      // If first factor fails, try second factor
      logger.info("First factor failed, trying second factor");
      response = await client.post(
        `/v1/client/sign_ins/${signInId}/attempt_second_factor`,
        { strategy: "email_code", code }
      );
    }

    const signInData = response.data.response || response.data;
    logger.info("2FA verification response:", { status: signInData.status });

    if (signInData.status === "complete") {
      logger.info(`2FA complete for signInId ${signInId}`);
      return { success: true, sessionToken: signInData.last_active_session_id };
    }

    return { success: false, error: "Invalid verification code" };
  } catch (error) {
    logger.error("Error in verify2FACode:", error);
    const errorMessage = error.response?.data?.errors?.[0]?.message || error.message;
    return { success: false, error: errorMessage || "Invalid verification code." };
  }
}

module.exports = {
  signUpWithEmailPassword,
  signInWithEmailPassword,
  verify2FACode,
  verifySignUpCode,
};