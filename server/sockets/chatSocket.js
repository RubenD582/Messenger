// chatSocket.js - Real-time chat socket handlers
const { producer } = require('../kafkaClient');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const db = require('../db');
const reliabilityService = require('../services/messageReliabilityService');

const publicKey = fs.readFileSync(path.join(__dirname, "../../config/keys/public_key.pem"), "utf8");

// Use shared Redis client with Sentinel support
const redis = require('../config/redisClient');

module.exports = (io) => {
  // JWT Authentication Middleware (same as friendSocket)
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

  // Socket Connection Handler
  io.on("connection", (socket) => {
    console.log("✅ Chat user connected:", socket.id, "UserId:", socket.userId);

    // Auto-register with Redis (same pattern as friendSocket)
    (async () => {
      try {
        // Store user-socket mapping
        await redis.setex(`user_socket:${socket.userId}`, 86400, socket.id); // 24 hours

        // Deliver queued offline messages
        const messages = await redis.lrange(`offline_messages:${socket.userId}`, 0, -1);
        if (messages.length > 0) {
          console.log(`📬 Delivering ${messages.length} queued messages to ${socket.userId}`);

          for (const msgStr of messages) {
            const msg = JSON.parse(msgStr);
            socket.emit('newMessage', msg);
          }

          // Clear the queue after delivery
          await redis.del(`offline_messages:${socket.userId}`);
        }

        // Send confirmation
        socket.emit("chatRegistered", {
          success: true,
          queuedMessages: messages.length
        });

      } catch (error) {
        console.error(`❌ Error registering chat user ${socket.userId}:`, error);
      }
    })();

    // Handle message acknowledgment (client confirms receipt)
    socket.on("messageAck", async (data) => {
      const { messageId, receivedAt } = data;

      if (!messageId) {
        return;
      }

      try {
        await reliabilityService.markDelivered(messageId, socket.userId);
        console.log(`✅ Message acknowledged: ${messageId} by user ${socket.userId}`);
      } catch (error) {
        console.error('Error handling message acknowledgment:', error);
      }
    });

    // Handle typing events (publish to Kafka)
    socket.on("typing", async (data) => {
      const { conversationId, isTyping } = data;

      if (!conversationId) {
        return socket.emit('error', { message: 'Conversation ID required for typing indicator' });
      }

      try {
        await producer.send({
          topic: 'typing-indicators',
          messages: [{
            key: conversationId,
            value: JSON.stringify({
              conversationId,
              userId: socket.userId,
              isTyping: !!isTyping,
              timestamp: new Date().toISOString()
            })
          }]
        });
      } catch (error) {
        console.error('Error publishing typing indicator:', error);
      }
    });

    // Handle message position updates (direct broadcast for low latency)
    socket.on("updateMessagePosition", async (data) => {
      const { messageId, conversationId, positionX, positionY, isPositioned, rotation, scale } = data;

      if (!messageId || !conversationId) {
        return socket.emit('error', { message: 'Message ID and Conversation ID required for position update' });
      }

      try {
        const now = new Date().toISOString();

        // Update database (non-blocking, fire and forget for performance)
        db.query(`
          UPDATE chats
          SET position_x = $1,
              position_y = $2,
              is_positioned = $3,
              positioned_by = $4,
              positioned_at = $5,
              rotation = $6,
              scale = $7
          WHERE message_id = $8
          AND conversation_id = $9
        `, [positionX, positionY, isPositioned, socket.userId, now, rotation || null, scale || null, messageId, conversationId])
          .catch(err => console.error('Error updating message position in DB:', err));

        // Prepare position update payload
        const positionUpdate = {
          messageId,
          conversationId,
          positionX,
          positionY,
          isPositioned,
          positionedBy: socket.userId,
          positionedAt: now
        };

        // Add rotation and scale if provided
        if (rotation !== undefined && rotation !== null) positionUpdate.rotation = rotation;
        if (scale !== undefined && scale !== null) positionUpdate.scale = scale;

        // Get the other user in conversation
        const [user1, user2] = conversationId.split('_');
        const otherUserId = user1 === socket.userId ? user2 : user1;

        // Broadcast to both users immediately (game-style networking)
        const otherSocketId = await redis.get(`user_socket:${otherUserId}`);

        // Send to other user
        if (otherSocketId) {
          io.to(otherSocketId).emit('messagePositionUpdate', positionUpdate);
        }

        // Echo back to sender for confirmation (client prediction reconciliation)
        socket.emit('messagePositionUpdate', positionUpdate);

        if (data._debug) {
          console.log(`📍 Position update: ${messageId} -> (${positionX}, ${positionY}) by ${socket.userId}`);
        }

      } catch (error) {
        console.error('Error handling position update:', error);
        socket.emit('error', { message: 'Failed to update message position' });
      }
    });


    // Handle disconnect
    socket.on("disconnect", async () => {
      try {
        if (socket.userId) {
          await redis.del(`user_socket:${socket.userId}`);
          console.log(`👋 Chat user ${socket.userId} disconnected`);
        }
      } catch (error) {
        console.error('Error handling disconnect:', error);
      }
    });
  });

  return io;
};
