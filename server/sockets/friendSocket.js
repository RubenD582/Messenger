// friendSocket.js
const { consumer } = require('../kafkaClient');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');

// Load public key for JWT verification
const publicKey = fs.readFileSync(path.join(__dirname, "../../config/keys/public_key.pem"), "utf8");

// Use shared Redis client with Sentinel support
const redis = require('../config/redisClient');

module.exports = (io) => {
  // Socket.io authentication middleware
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.split(' ')[1];

      if (!token) {
        return next(new Error('Authentication error: No token provided'));
      }

      const decoded = jwt.verify(token, publicKey, { algorithms: ["RS256"] });
      socket.userId = decoded.userId;
      next();
    } catch (error) {
      console.error('Socket authentication failed:', error.message);
      next(new Error('Authentication error: Invalid token'));
    }
  });

  // Connect Kafka consumer and subscribe to friend-events topic
  (async () => {
    try {
      await consumer.connect();
      await consumer.subscribe({ topic: 'friend-events', fromBeginning: false });
      console.log('Kafka consumer connected and subscribed to friend-events');

      // Kafka consumer
      await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const eventData = JSON.parse(message.value.toString());
            const userId = message.key.toString();

            // Get socketId from Redis for userId
            const userSocketId = await redis.get(`user_socket:${userId}`);

            // Emit the event to user if online
            if (userSocketId) {
              console.log(`Emitting ${eventData.event} event to user ${userId} with socket ${userSocketId}`);
              io.to(userSocketId).emit(eventData.event, eventData.payload);
            } else {
              // User is offline - notification already queued by API
              console.log(`User ${userId} is offline - notification queued`);
            }

            // Invalidate relevant cache
            await invalidateUserCache(userId);
            if (eventData.payload.friendId) {
              await invalidateUserCache(eventData.payload.friendId);
            }
          } catch (error) {
            console.error('Error processing Kafka message:', error);
          }
        },
      });

    } catch (error) {
      console.error('Failed to setup Kafka consumer:', error);
    }
  })();

  io.on("connection", (socket) => {
    console.log("User connected:", socket.id, "UserId:", socket.userId);

    // Auto-register with verified userId from JWT and join user's room
    (async () => {
      try {
        // Join user-specific room for Socket.IO targeted emissions
        socket.join(socket.userId);

        // Store socket mapping in Redis with 24h expiry (for backward compatibility)
        await redis.setex(`user_socket:${socket.userId}`, 86400, socket.id);
        console.log(`User ${socket.userId} auto-registered and joined room with socket ID: ${socket.id}`);

        socket.emit("registered", { success: true });
      } catch (error) {
        console.error(`Error auto-registering user ${socket.userId}:`, error);
        socket.emit("registered", { success: false, error: "Failed to register user" });
      }
    })();

    // Handle disconnection
    socket.on("disconnect", async () => {
      try {
        if (socket.userId) {
          await redis.del(`user_socket:${socket.userId}`);
          console.log(`User ${socket.userId} disconnected and removed from Redis`);
        }
      } catch (error) {
        console.error('Error handling disconnect:', error);
      }
    });
  });

  // Optimized cache invalidation using specific key patterns
  async function invalidateUserCache(userId) {
    try {
      const keysToDelete = [
        `pending_requests:${userId}`,
        `pending_requests_count:${userId}`,
        `friends_list:${userId}:accepted`,
        `friends_list:${userId}:pending`
      ];

      const pipeline = redis.pipeline();
      keysToDelete.forEach(key => pipeline.del(key));
      await pipeline.exec();

      console.log(`Cache invalidated for user ${userId} (${keysToDelete.length} specific keys)`);
    } catch (error) {
      console.error(`Error invalidating cache for user ${userId}:`, error);
    }
  }

  // Graceful shutdown
  process.on('SIGTERM', async () => {
    try {
      await consumer.disconnect();
      await redis.quit();
      console.log('Gracefully disconnected from Kafka and Redis');
    } catch (error) {
      console.error('Error during graceful shutdown:', error);
    }
  });

  return io;
};