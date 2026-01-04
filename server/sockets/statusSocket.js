// statusSocket.js - Real-time status updates with Kafka integration
const { statusConsumer } = require('../kafkaClient');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const db = require('../db');

const publicKey = fs.readFileSync(path.join(__dirname, "../../config/keys/public_key.pem"), "utf8");
const redis = require('../config/redisClient');

module.exports = (io) => {
  // KAFKA CONSUMER: Status Events
  (async () => {
    try {
      await statusConsumer.subscribe({ topic: 'status-events', fromBeginning: false });

      await statusConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const eventData = JSON.parse(message.value.toString());
            const { event, data } = eventData;

            console.log(`Processing status event: ${event}`, data);

            if (event === 'statusCreated') {
              const { userId } = data;

              // Get all friends of the user who created the status
              const friendsResult = await db.query(`
                SELECT
                  CASE
                    WHEN user_id = $1 THEN friend_id
                    ELSE user_id
                  END as friend_id
                FROM friends
                WHERE (user_id = $1 OR friend_id = $1)
                AND status = 'accepted'
              `, [userId]);

              // Broadcast to all friends
              for (const row of friendsResult.rows) {
                const friendId = row.friend_id;
                const friendSocketId = await redis.get(`user_socket:${friendId}`);

                if (friendSocketId) {
                  io.to(friendSocketId).emit('statusCreated', data);
                  console.log(`✅ Emitted statusCreated to friend ${friendId}`);
                }
              }

              // Also emit to the user who created it (for real-time UI update)
              const userSocketId = await redis.get(`user_socket:${userId}`);
              if (userSocketId) {
                io.to(userSocketId).emit('statusCreated', data);
                console.log(`✅ Emitted statusCreated to creator ${userId}`);
              }

            } else if (event === 'statusDeleted') {
              const { userId, id } = data;

              // Get all friends of the user
              const friendsResult = await db.query(`
                SELECT
                  CASE
                    WHEN user_id = $1 THEN friend_id
                    ELSE user_id
                  END as friend_id
                FROM friends
                WHERE (user_id = $1 OR friend_id = $1)
                AND status = 'accepted'
              `, [userId]);

              // Broadcast to all friends
              for (const row of friendsResult.rows) {
                const friendId = row.friend_id;
                const friendSocketId = await redis.get(`user_socket:${friendId}`);

                if (friendSocketId) {
                  io.to(friendSocketId).emit('statusDeleted', data);
                  console.log(`✅ Emitted statusDeleted to friend ${friendId}`);
                }
              }

              // Also emit to the user who deleted it
              const userSocketId = await redis.get(`user_socket:${userId}`);
              if (userSocketId) {
                io.to(userSocketId).emit('statusDeleted', data);
                console.log(`✅ Emitted statusDeleted to creator ${userId}`);
              }
            }

          } catch (error) {
            console.error('Error processing status event:', error);
          }
        }
      });

      console.log('✅ Status consumer connected and subscribed to status-events');
    } catch (error) {
      console.error('❌ Failed to setup status consumer:', error);
    }
  })();

  return io;
};
