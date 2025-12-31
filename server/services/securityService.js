const redisClient = require("../config/redisClient");
const jwt = require("jsonwebtoken");
const fs = require("fs");
const path = require("path");

const privateKey = fs.readFileSync(path.join(__dirname, "../../config/keys/private_key.pem"), "utf8");

class SecurityService {
  // ==========================================
  // FAILED LOGIN TRACKING (Instagram-style)
  // ==========================================

  /**
   * Track failed login attempt
   * Returns delay in seconds if user should wait
   */
  static async trackFailedLogin(email) {
    const key = `failed_login:${email}`;
    const attempts = await redisClient.incr(key);

    // Set expiry on first attempt (resets after 30 minutes of no attempts)
    if (attempts === 1) {
      await redisClient.expire(key, 30 * 60);
    }

    // Progressive delays like Instagram
    let delaySeconds = 0;
    if (attempts >= 10) {
      delaySeconds = 30 * 60; // 30 minutes
    } else if (attempts >= 7) {
      delaySeconds = 15 * 60; // 15 minutes
    } else if (attempts >= 5) {
      delaySeconds = 5 * 60; // 5 minutes
    } else if (attempts >= 3) {
      delaySeconds = 60; // 1 minute
    }

    if (delaySeconds > 0) {
      // Store when user can try again
      const unlockTime = Math.floor(Date.now() / 1000) + delaySeconds;
      await redisClient.set(`login_lockout:${email}`, unlockTime, 'EX', delaySeconds);
    }

    return { attempts, delaySeconds };
  }

  /**
   * Check if user is currently locked out
   */
  static async checkLoginLockout(email) {
    const unlockTime = await redisClient.get(`login_lockout:${email}`);
    if (!unlockTime) return { locked: false };

    const now = Math.floor(Date.now() / 1000);
    const timeRemaining = parseInt(unlockTime) - now;

    if (timeRemaining > 0) {
      return { locked: true, waitSeconds: timeRemaining };
    }

    return { locked: false };
  }

  /**
   * Clear failed login attempts on successful login
   */
  static async clearFailedLogins(email) {
    await redisClient.del(`failed_login:${email}`);
    await redisClient.del(`login_lockout:${email}`);
  }

  // ==========================================
  // SINGLE DEVICE SESSION ENFORCEMENT
  // ==========================================

  /**
   * Store active session for user (one device only)
   * Invalidates previous session
   */
  static async createSession(userId, refreshToken, ipAddress, userAgent) {
    const sessionKey = `active_session:${userId}`;

    // Get old session to invalidate it
    const oldSession = await redisClient.get(sessionKey);
    if (oldSession) {
      const { refreshToken: oldRefreshToken } = JSON.parse(oldSession);
      // Blacklist old refresh token
      await redisClient.set(`blacklist:${oldRefreshToken}`, '1', 'EX', 7 * 24 * 60 * 60);
    }

    // Store new session
    const sessionData = {
      refreshToken,
      ipAddress,
      userAgent,
      createdAt: new Date().toISOString()
    };

    // Session expires in 7 days (same as refresh token)
    await redisClient.set(sessionKey, JSON.stringify(sessionData), 'EX', 7 * 24 * 60 * 60);
  }

  /**
   * Get active session for user
   */
  static async getActiveSession(userId) {
    const sessionKey = `active_session:${userId}`;
    const sessionData = await redisClient.get(sessionKey);
    return sessionData ? JSON.parse(sessionData) : null;
  }

  /**
   * Invalidate user's session
   */
  static async invalidateSession(userId) {
    const sessionKey = `active_session:${userId}`;
    const session = await redisClient.get(sessionKey);

    if (session) {
      const { refreshToken } = JSON.parse(session);
      // Blacklist the refresh token
      await redisClient.set(`blacklist:${refreshToken}`, '1', 'EX', 7 * 24 * 60 * 60);
      await redisClient.del(sessionKey);
    }
  }

  // ==========================================
  // IP SWITCHING DETECTION
  // ==========================================

  /**
   * Track IP for session and detect switching
   */
  static async checkIPSwitch(userId, currentIP, sessionIP) {
    if (currentIP === sessionIP) {
      return { switched: false };
    }

    // IP has changed - log it
    const switchKey = `ip_switch:${userId}`;
    const switches = await redisClient.incr(switchKey);
    await redisClient.expire(switchKey, 60 * 60); // Track for 1 hour

    // If more than 3 IP switches in an hour, flag as suspicious
    const suspicious = switches > 3;

    // Log the IP switch
    await redisClient.lPush(`ip_history:${userId}`, JSON.stringify({
      from: sessionIP,
      to: currentIP,
      timestamp: new Date().toISOString()
    }));
    await redisClient.lTrim(`ip_history:${userId}`, 0, 9); // Keep last 10

    return {
      switched: true,
      suspicious,
      switchCount: switches
    };
  }

  // ==========================================
  // REFRESH TOKEN ROTATION
  // ==========================================

  /**
   * Generate access and refresh tokens
   */
  static generateTokens(user) {
    const accessToken = jwt.sign(
      { email: user.email, userId: user.id },
      privateKey,
      { algorithm: "RS256", expiresIn: "15m" } // Short-lived access token
    );

    const refreshToken = jwt.sign(
      { email: user.email, userId: user.id, type: 'refresh' },
      privateKey,
      { algorithm: "RS256", expiresIn: "7d" } // Longer-lived refresh token
    );

    return { accessToken, refreshToken };
  }

  /**
   * Store refresh token in Redis
   */
  static async storeRefreshToken(userId, refreshToken) {
    const key = `refresh_token:${userId}`;
    await redisClient.set(key, refreshToken, 'EX', 7 * 24 * 60 * 60); // 7 days
  }

  /**
   * Verify refresh token is valid and not blacklisted
   */
  static async verifyRefreshToken(refreshToken) {
    // Check if blacklisted
    const blacklisted = await redisClient.get(`blacklist:${refreshToken}`);
    if (blacklisted) {
      return { valid: false, reason: 'Token has been revoked' };
    }

    return { valid: true };
  }

  /**
   * Revoke all tokens for user (password change, security breach)
   */
  static async revokeAllUserTokens(userId) {
    // Invalidate active session (which blacklists refresh token)
    await this.invalidateSession(userId);

    // Also clear stored refresh token
    await redisClient.del(`refresh_token:${userId}`);

    // Clear IP history
    await redisClient.del(`ip_history:${userId}`);
    await redisClient.del(`ip_switch:${userId}`);
  }

  // ==========================================
  // PER-USER RATE LIMITING
  // ==========================================

  /**
   * Check rate limit for user (100 requests per minute)
   */
  static async checkUserRateLimit(userId) {
    const key = `rate_limit:user:${userId}`;
    const requests = await redisClient.incr(key);

    // Set expiry on first request
    if (requests === 1) {
      await redisClient.expire(key, 60); // 1 minute window
    }

    const limit = 100; // requests per minute
    const remaining = Math.max(0, limit - requests);
    const exceeded = requests > limit;

    return {
      allowed: !exceeded,
      limit,
      remaining,
      requests
    };
  }
}

module.exports = SecurityService;
