// friendSocket.js
const Redis = require('ioredis');
const { consumer } = require('../kafkaClient');

// Initialize Redis client
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis',
  port: process.env.REDIS_PORT || 6379
});

module.exports = (io) => {
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
            const friendSocketId = await redis.get(`user_socket:${eventData.payload.friendId}`);

            // Emit the event to user if the socketId exists
            if (userSocketId) {
              console.log(`Emitting ${eventData.event} event to user ${userId} with socket ${userSocketId}`);
              io.to(userSocketId).emit(eventData.event, eventData.payload);
            }

            // Emit the event to friend if the socketId exists
            if (friendSocketId) {
              console.log(`Emitting ${eventData.event} event to friend ${eventData.payload.friendId} with socket ${friendSocketId}`);
              io.to(friendSocketId).emit(eventData.event, eventData.payload);
            }

            // Invalidate relevant cache for user and friend
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
    console.log("User connected:", socket.id);
    
    // Store userId when they connect - now in Redis
    socket.on("register", async (userId) => {
      try {
        // Store socket mapping in Redis with 24h expiry
        await redis.setex(`user_socket:${userId}`, 86400, socket.id);
        console.log(`User ${userId} registered with socket ID: ${socket.id}`);
        socket.emit("registered", { success: true });
        
        // Store userId in socket data for disconnect handling
        socket.data.userId = userId;
      } catch (error) {
        console.error(`Error registering user ${userId}:`, error);
        socket.emit("registered", { success: false, error: "Failed to register user" });
      }
    });

    // Handle disconnection
    socket.on("disconnect", async () => {
      try {
        if (socket.data.userId) {
          await redis.del(`user_socket:${socket.data.userId}`);
          console.log(`User ${socket.data.userId} disconnected and removed from Redis`);
        }
      } catch (error) {
        console.error('Error handling disconnect:', error);
      }
    });
  });

  // Function to invalidate user's cache in Redis
  async function invalidateUserCache(userId) {
    try {
      await Promise.all([
        redis.del(`pending_requests:${userId}`),
        redis.del(`pending_requests_count:${userId}`),
        redis.del(`friends_list:${userId}`)
      ]);
      console.log(`Cache invalidated for user ${userId}`);
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