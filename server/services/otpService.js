const crypto = require('crypto');
const redisClient = require('../config/redisClient');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/combined.log' }),
  ],
});

class OTPService {
  constructor() {
    this.OTP_EXPIRY = 10 * 60; // 10 minutes in seconds
    this.MAX_ATTEMPTS = 5; // Maximum verification attempts
    this.RATE_LIMIT_WINDOW = 60; // 1 minute in seconds
    this.MAX_OTP_REQUESTS = 3; // Max 3 OTP requests per minute per email
  }

  /**
   * Generate a cryptographically secure 6-digit OTP
   * Uses crypto.randomInt for secure random generation
   * @returns {string} 6-digit OTP code
   */
  generateOTP() {
    // Use crypto.randomInt for cryptographically secure random numbers
    // Range: 100000 to 999999 (ensures 6 digits)
    const otp = crypto.randomInt(100000, 1000000).toString();
    logger.info('OTP generated (not logged for security)');
    return otp;
  }

  /**
   * Hash OTP before storing in Redis
   * Provides additional security layer
   * @param {string} otp - Plain OTP code
   * @returns {string} Hashed OTP
   */
  hashOTP(otp) {
    return crypto.createHash('sha256').update(otp).digest('hex');
  }

  /**
   * Check if email has exceeded OTP request rate limit
   * @param {string} email - User email
   * @returns {Promise<boolean>} True if rate limited
   */
  async isRateLimited(email) {
    const rateLimitKey = `otp:ratelimit:${email}`;
    const count = await redisClient.get(rateLimitKey);

    if (count && parseInt(count) >= this.MAX_OTP_REQUESTS) {
      logger.warn(`OTP rate limit exceeded for email: ${email}`);
      return true;
    }
    return false;
  }

  /**
   * Increment OTP request counter for rate limiting
   * @param {string} email - User email
   */
  async incrementRateLimit(email) {
    const rateLimitKey = `otp:ratelimit:${email}`;
    const current = await redisClient.get(rateLimitKey);

    if (current) {
      await redisClient.incr(rateLimitKey);
    } else {
      await redisClient.set(rateLimitKey, '1', 'EX', this.RATE_LIMIT_WINDOW);
    }
  }

  /**
   * Store OTP in Redis with expiration and attempt counter
   * @param {string} email - User email
   * @param {string} otp - Plain OTP code
   * @param {string} purpose - 'registration' or 'login' or '2fa'
   * @returns {Promise<boolean>} Success status
   */
  async storeOTP(email, otp, purpose = 'registration') {
    try {
      // Check rate limit
      if (await this.isRateLimited(email)) {
        return { success: false, error: 'Too many OTP requests. Please try again later.' };
      }

      const hashedOTP = this.hashOTP(otp);
      const otpKey = `otp:${purpose}:${email}`;
      const attemptsKey = `otp:attempts:${purpose}:${email}`;

      // Store hashed OTP with expiration (ioredis uses lowercase 'setex')
      await redisClient.set(otpKey, hashedOTP, 'EX', this.OTP_EXPIRY);

      // Initialize attempts counter
      await redisClient.set(attemptsKey, '0', 'EX', this.OTP_EXPIRY);

      // Increment rate limit counter
      await this.incrementRateLimit(email);

      logger.info(`OTP stored for ${email} with purpose: ${purpose}`);
      return { success: true };
    } catch (error) {
      logger.error('Error storing OTP:', error);
      return { success: false, error: 'Failed to generate OTP' };
    }
  }

  /**
   * Verify OTP code
   * @param {string} email - User email
   * @param {string} otp - OTP code to verify
   * @param {string} purpose - 'registration' or 'login' or '2fa'
   * @returns {Promise<Object>} Verification result
   */
  async verifyOTP(email, otp, purpose = 'registration') {
    try {
      const otpKey = `otp:${purpose}:${email}`;
      const attemptsKey = `otp:attempts:${purpose}:${email}`;

      // Check if OTP exists
      const storedHashedOTP = await redisClient.get(otpKey);
      if (!storedHashedOTP) {
        logger.warn(`OTP not found or expired for ${email}`);
        return { success: false, error: 'OTP has expired or does not exist' };
      }

      // Check attempts
      const attempts = await redisClient.get(attemptsKey);
      if (attempts && parseInt(attempts) >= this.MAX_ATTEMPTS) {
        logger.warn(`Max OTP verification attempts exceeded for ${email}`);
        // Delete OTP to prevent further attempts
        await this.deleteOTP(email, purpose);
        return { success: false, error: 'Maximum verification attempts exceeded' };
      }

      // Increment attempts
      await redisClient.incr(attemptsKey);

      // Verify OTP
      const hashedInputOTP = this.hashOTP(otp);
      if (hashedInputOTP !== storedHashedOTP) {
        logger.warn(`Invalid OTP attempt for ${email}`);
        return { success: false, error: 'Invalid OTP code' };
      }

      // OTP verified successfully - delete it
      await this.deleteOTP(email, purpose);

      logger.info(`OTP verified successfully for ${email}`);
      return { success: true };
    } catch (error) {
      logger.error('Error verifying OTP:', error);
      return { success: false, error: 'Failed to verify OTP' };
    }
  }

  /**
   * Delete OTP from Redis
   * @param {string} email - User email
   * @param {string} purpose - 'registration' or 'login' or '2fa'
   */
  async deleteOTP(email, purpose = 'registration') {
    const otpKey = `otp:${purpose}:${email}`;
    const attemptsKey = `otp:attempts:${purpose}:${email}`;

    await redisClient.del(otpKey);
    await redisClient.del(attemptsKey);

    logger.info(`OTP deleted for ${email}`);
  }

  /**
   * Check if OTP exists for an email
   * @param {string} email - User email
   * @param {string} purpose - 'registration' or 'login' or '2fa'
   * @returns {Promise<boolean>} True if OTP exists
   */
  async otpExists(email, purpose = 'registration') {
    const otpKey = `otp:${purpose}:${email}`;
    const exists = await redisClient.exists(otpKey);
    return exists === 1;
  }
}

module.exports = new OTPService();
