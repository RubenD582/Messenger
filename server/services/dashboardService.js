// dashboardService.js - Comprehensive dashboard data aggregation
const redis = require('../config/redisClient');
const db = require('../db');
const reliabilityService = require('./messageReliabilityService');

class DashboardService {
  constructor() {
    this.ERROR_LOG_KEY = 'dashboard:errors';
    this.METRICS_KEY = 'dashboard:metrics';
    this.HOURLY_STATS_KEY = 'dashboard:hourly';
    this.DAILY_STATS_KEY = 'dashboard:daily';
  }

  /**
   * Log an error for dashboard tracking
   */
  async logError(error, context = {}) {
    try {
      const errorEntry = {
        timestamp: new Date().toISOString(),
        message: error.message,
        stack: error.stack,
        type: error.name || 'Error',
        context,
        severity: this.categorizeError(error),
      };

      // Add to sorted set (scored by timestamp)
      await redis.zadd(
        this.ERROR_LOG_KEY,
        Date.now(),
        JSON.stringify(errorEntry)
      );

      // Keep only last 1000 errors
      await redis.zremrangebyrank(this.ERROR_LOG_KEY, 0, -1001);

      // Increment hourly error counter
      const hourKey = this.getHourKey();
      await redis.hincrby(hourKey, 'errors', 1);
      await redis.expire(hourKey, 86400 * 7); // Keep for 7 days

    } catch (err) {
      console.error('Failed to log error to dashboard:', err);
    }
  }

  /**
   * Categorize error severity
   */
  categorizeError(error) {
    const message = error.message?.toLowerCase() || '';

    if (message.includes('econnrefused') || message.includes('timeout')) {
      return 'critical';
    }
    if (message.includes('validation') || message.includes('required')) {
      return 'warning';
    }
    return 'error';
  }

  /**
   * Get hourly key for current hour
   */
  getHourKey(date = new Date()) {
    const hourTimestamp = new Date(date);
    hourTimestamp.setMinutes(0, 0, 0);
    return `${this.HOURLY_STATS_KEY}:${hourTimestamp.toISOString()}`;
  }

  /**
   * Get daily key for current day
   */
  getDayKey(date = new Date()) {
    const dayTimestamp = new Date(date);
    dayTimestamp.setHours(0, 0, 0, 0);
    return `${this.DAILY_STATS_KEY}:${dayTimestamp.toISOString()}`;
  }

  /**
   * Track message sent (called from chatMessageService)
   */
  async trackMessageSent() {
    try {
      const hourKey = this.getHourKey();
      await redis.hincrby(hourKey, 'messages_sent', 1);
      await redis.expire(hourKey, 86400 * 7);

      const dayKey = this.getDayKey();
      await redis.hincrby(dayKey, 'messages_sent', 1);
      await redis.expire(dayKey, 86400 * 30);
    } catch (err) {
      console.error('Failed to track message sent:', err);
    }
  }

  /**
   * Track message delivered
   */
  async trackMessageDelivered() {
    try {
      const hourKey = this.getHourKey();
      await redis.hincrby(hourKey, 'messages_delivered', 1);
      await redis.expire(hourKey, 86400 * 7);

      const dayKey = this.getDayKey();
      await redis.hincrby(dayKey, 'messages_delivered', 1);
      await redis.expire(dayKey, 86400 * 30);
    } catch (err) {
      console.error('Failed to track message delivered:', err);
    }
  }

  /**
   * Track message failed
   */
  async trackMessageFailed() {
    try {
      const hourKey = this.getHourKey();
      await redis.hincrby(hourKey, 'messages_failed', 1);
      await redis.expire(hourKey, 86400 * 7);

      const dayKey = this.getDayKey();
      await redis.hincrby(dayKey, 'messages_failed', 1);
      await redis.expire(dayKey, 86400 * 30);
    } catch (err) {
      console.error('Failed to track message failed:', err);
    }
  }

  /**
   * Get recent errors (last N errors)
   */
  async getRecentErrors(limit = 100) {
    try {
      const errors = await redis.zrevrange(this.ERROR_LOG_KEY, 0, limit - 1);
      return errors.map(e => JSON.parse(e));
    } catch (error) {
      console.error('Error getting recent errors:', error);
      return [];
    }
  }

  /**
   * Get error statistics
   */
  async getErrorStats() {
    try {
      const now = Date.now();
      const oneHourAgo = now - (60 * 60 * 1000);
      const oneDayAgo = now - (24 * 60 * 60 * 1000);

      const allErrors = await redis.zrangebyscore(
        this.ERROR_LOG_KEY,
        oneDayAgo,
        now
      );

      const errors = allErrors.map(e => JSON.parse(e));
      const lastHourErrors = errors.filter(e =>
        new Date(e.timestamp).getTime() > oneHourAgo
      );

      // Group by severity
      const bySeverity = {
        critical: errors.filter(e => e.severity === 'critical').length,
        error: errors.filter(e => e.severity === 'error').length,
        warning: errors.filter(e => e.severity === 'warning').length,
      };

      // Group by type
      const byType = {};
      errors.forEach(e => {
        byType[e.type] = (byType[e.type] || 0) + 1;
      });

      return {
        total24h: errors.length,
        lastHour: lastHourErrors.length,
        bySeverity,
        byType,
      };
    } catch (error) {
      console.error('Error getting error stats:', error);
      return {
        total24h: 0,
        lastHour: 0,
        bySeverity: { critical: 0, error: 0, warning: 0 },
        byType: {},
      };
    }
  }

  /**
   * Get hourly statistics for the last N hours
   */
  async getHourlyStats(hours = 24) {
    try {
      const stats = [];
      const now = new Date();

      for (let i = hours - 1; i >= 0; i--) {
        const hourDate = new Date(now.getTime() - (i * 60 * 60 * 1000));
        const hourKey = this.getHourKey(hourDate);

        const data = await redis.hgetall(hourKey);

        stats.push({
          hour: hourDate.toISOString(),
          messagesSent: parseInt(data.messages_sent || 0),
          messagesDelivered: parseInt(data.messages_delivered || 0),
          messagesFailed: parseInt(data.messages_failed || 0),
          errors: parseInt(data.errors || 0),
        });
      }

      return stats;
    } catch (error) {
      console.error('Error getting hourly stats:', error);
      return [];
    }
  }

  /**
   * Get daily statistics for the last N days
   */
  async getDailyStats(days = 30) {
    try {
      const stats = [];
      const now = new Date();

      for (let i = days - 1; i >= 0; i--) {
        const dayDate = new Date(now.getTime() - (i * 24 * 60 * 60 * 1000));
        const dayKey = this.getDayKey(dayDate);

        const data = await redis.hgetall(dayKey);

        stats.push({
          day: dayDate.toISOString().split('T')[0],
          messagesSent: parseInt(data.messages_sent || 0),
          messagesDelivered: parseInt(data.messages_delivered || 0),
          messagesFailed: parseInt(data.messages_failed || 0),
          errors: parseInt(data.errors || 0),
        });
      }

      return stats;
    } catch (error) {
      console.error('Error getting daily stats:', error);
      return [];
    }
  }

  /**
   * Get current system metrics
   */
  async getCurrentMetrics() {
    try {
      // Get reliability metrics
      const reliability = await reliabilityService.getMetrics();

      // Get active connections
      const userSocketKeys = await redis.keys('user_socket:*');
      const activeConnections = userSocketKeys.length;

      // Get total messages in DB
      const totalMessagesResult = await db.query('SELECT COUNT(*) as count FROM chats');
      const totalMessages = parseInt(totalMessagesResult.rows[0].count);

      // Get total users
      const totalUsersResult = await db.query('SELECT COUNT(*) as count FROM users');
      const totalUsers = parseInt(totalUsersResult.rows[0].count);

      // Get messages in last hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const recentMessagesResult = await db.query(
        'SELECT COUNT(*) as count FROM chats WHERE timestamp > $1',
        [oneHourAgo]
      );
      const messagesLastHour = parseInt(recentMessagesResult.rows[0].count);

      return {
        activeConnections,
        totalMessages,
        totalUsers,
        messagesLastHour,
        reliability: reliability || {},
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      console.error('Error getting current metrics:', error);
      return {
        activeConnections: 0,
        totalMessages: 0,
        totalUsers: 0,
        messagesLastHour: 0,
        reliability: {},
        timestamp: new Date().toISOString(),
      };
    }
  }

  /**
   * Get comprehensive dashboard data
   */
  async getDashboardData() {
    try {
      const [
        currentMetrics,
        errorStats,
        recentErrors,
        hourlyStats,
        dailyStats,
      ] = await Promise.all([
        this.getCurrentMetrics(),
        this.getErrorStats(),
        this.getRecentErrors(50),
        this.getHourlyStats(24),
        this.getDailyStats(7),
      ]);

      return {
        current: currentMetrics,
        errors: {
          stats: errorStats,
          recent: recentErrors,
        },
        timeSeries: {
          hourly: hourlyStats,
          daily: dailyStats,
        },
        generatedAt: new Date().toISOString(),
      };
    } catch (error) {
      console.error('Error getting dashboard data:', error);
      throw error;
    }
  }
}

module.exports = new DashboardService();
