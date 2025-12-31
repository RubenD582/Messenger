const SecurityService = require("../services/securityService");

/**
 * Rate limit middleware per authenticated user
 * Requires authenticateToken to run first
 */
exports.userRateLimiter = async (req, res, next) => {
  if (!req.user || !req.user.userId) {
    // If no user authenticated, skip user-based rate limiting
    // (IP-based rate limiting still applies)
    return next();
  }

  try {
    const rateLimit = await SecurityService.checkUserRateLimit(req.user.userId);

    if (!rateLimit.allowed) {
      return res.status(429).json({
        message: "Too many requests. Please slow down.",
        retryAfter: 60 // seconds
      });
    }

    // Add rate limit info to response headers
    res.setHeader('X-RateLimit-Limit', rateLimit.limit);
    res.setHeader('X-RateLimit-Remaining', rateLimit.remaining);

    next();
  } catch (error) {
    console.error("Error in user rate limiter:", error);
    // On error, allow request to proceed (fail open)
    next();
  }
};
