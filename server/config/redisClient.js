// redisClient.js - Shared Redis Sentinel configuration
const Redis = require('ioredis');

/**
 * Create Redis client with Sentinel support for high availability
 * Automatically fails over to replica if master goes down
 */
function createRedisClient() {
  // Check if we're using Sentinel (production/docker) or standalone (development)
  const useSentinel = process.env.REDIS_SENTINEL === 'true' || process.env.NODE_ENV === 'production';

  if (useSentinel) {
    console.log('🔴 Connecting to Redis Sentinel cluster...');

    // Connect to Redis Sentinel for automatic failover
    return new Redis({
      sentinels: [
        { host: process.env.REDIS_SENTINEL_HOST_1 || 'redis-sentinel-1', port: 26379 },
        { host: process.env.REDIS_SENTINEL_HOST_2 || 'redis-sentinel-2', port: 26379 },
        { host: process.env.REDIS_SENTINEL_HOST_3 || 'redis-sentinel-3', port: 26379 },
      ],
      name: 'mymaster', // Master name configured in sentinel.conf
      password: process.env.REDIS_PASSWORD || 'redispass123',

      // Connection settings
      sentinelRetryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        console.log(`Sentinel retry attempt ${times}, waiting ${delay}ms`);
        return delay;
      },

      // Retry connection on failure
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        console.log(`Redis retry attempt ${times}, waiting ${delay}ms`);
        return delay;
      },

      // Enable reconnection
      enableReadyCheck: true,
      maxRetriesPerRequest: 3,
    });
  } else {
    console.log('🔵 Connecting to standalone Redis (development mode)...');

    // Standalone Redis for local development
    return new Redis({
      host: process.env.REDIS_HOST || 'localhost',
      port: process.env.REDIS_PORT || 6379,
      password: process.env.REDIS_PASSWORD || undefined,

      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
    });
  }
}

// Create singleton instance
const redis = createRedisClient();

// Event handlers
redis.on('connect', () => {
  console.log('✅ Redis client connected');
});

redis.on('ready', () => {
  console.log('✅ Redis client ready');
});

redis.on('error', (err) => {
  console.error('❌ Redis error:', err.message);
});

redis.on('close', () => {
  console.log('⚠️  Redis connection closed');
});

redis.on('reconnecting', () => {
  console.log('🔄 Redis reconnecting...');
});

// Sentinel-specific events
if (process.env.REDIS_SENTINEL === 'true' || process.env.NODE_ENV === 'production') {
  redis.on('+switch-master', (data) => {
    console.log('🔄 Redis Sentinel: Master switched!', data);
  });

  redis.on('failover', (data) => {
    console.log('🚨 Redis Sentinel: Failover in progress', data);
  });
}

module.exports = redis;
