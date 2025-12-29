// chatSocket.js - Real-time chat with Kafka integration
const { messageConsumer, typingConsumer, receiptConsumer, producer } = require('../kafkaClient');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const db = require('../db');

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

  // KAFKA CONSUMER 1: Chat Messages
  (async () => {
    try {
      await messageConsumer.subscribe({ topic: 'chat-messages', fromBeginning: false });

      await messageConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const messageData = JSON.parse(message.value.toString());
            const { messageId, senderId, receiverId, conversationId, sequenceId } = messageData;

            console.log(`Processing message ${messageId} in conversation ${conversationId}`);

            // Store in database with idempotency
            await db.query(`
              INSERT INTO chats (
                message_id, sender_id, receiver_id, message, seen, timestamp,
                sequence_id, conversation_id, message_type, metadata,
                kafka_partition, kafka_offset, version,
                position_x, position_y, is_positioned
              ) VALUES ($1, $2, $3, $4, false, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
              ON CONFLICT (conversation_id, sequence_id) DO NOTHING
            `, [
              messageData.messageId,
              messageData.senderId,
              messageData.receiverId,
              messageData.message,
              messageData.timestamp,
              messageData.sequenceId,
              messageData.conversationId,
              messageData.messageType || 'text',
              JSON.stringify(messageData.metadata || {}),
              partition.toString(),
              message.offset,
              Math.floor(Date.now() / 1000),
              messageData.positionX || null,
              messageData.positionY || null,
              messageData.isPositioned || false
            ]);

            // Get socket IDs from Redis
            const senderSocketId = await redis.get(`user_socket:${senderId}`);
            const receiverSocketId = await redis.get(`user_socket:${receiverId}`);

            console.log(`📤 Emitting message ${messageId}:`);
            console.log(`   Sender: ${senderId} → Socket: ${senderSocketId || 'NOT FOUND'}`);
            console.log(`   Receiver: ${receiverId} → Socket: ${receiverSocketId || 'NOT FOUND'}`);

            // Emit to both sender and receiver
            if (senderSocketId) {
              io.to(senderSocketId).emit('newMessage', messageData);
              console.log(`   ✅ Emitted to sender socket ${senderSocketId}`);
            } else {
              console.log(`   ❌ Sender socket not found - user may be offline`);
            }

            if (receiverSocketId) {
              io.to(receiverSocketId).emit('newMessage', messageData);
              console.log(`   ✅ Emitted to receiver socket ${receiverSocketId}`);
              // Invalidate unread count cache
              await redis.del(`unread_count:${receiverId}`);
            } else {
              console.log(`   ❌ Receiver socket not found - queuing offline`);
              // Queue for offline delivery
              await queueOfflineMessage(receiverId, messageData);
            }

          } catch (error) {
            console.error('Error processing chat message:', error);
          }
        }
      });

      console.log('✅ Message consumer connected and subscribed to chat-messages');
    } catch (error) {
      console.error('❌ Failed to setup message consumer:', error);
    }
  })();

  // KAFKA CONSUMER 2: Typing Indicators
  (async () => {
    try {
      await typingConsumer.subscribe({ topic: 'typing-indicators', fromBeginning: false });

      await typingConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const typingData = JSON.parse(message.value.toString());
            const { conversationId, userId, isTyping } = typingData;

            // Get the other user in conversation
            const [user1, user2] = conversationId.split('_');
            const otherUserId = user1 === userId ? user2 : user1;

            const otherSocketId = await redis.get(`user_socket:${otherUserId}`);

            if (otherSocketId) {
              io.to(otherSocketId).emit('typingIndicator', {
                conversationId,
                userId,
                isTyping,
                timestamp: typingData.timestamp
              });
            }

          } catch (error) {
            console.error('Error processing typing indicator:', error);
          }
        }
      });

      console.log('✅ Typing consumer connected and subscribed to typing-indicators');
    } catch (error) {
      console.error('❌ Failed to setup typing consumer:', error);
    }
  })();

  // KAFKA CONSUMER 3: Read Receipts
  (async () => {
    try {
      await receiptConsumer.subscribe({ topic: 'read-receipts', fromBeginning: false });

      await receiptConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const receiptData = JSON.parse(message.value.toString());
            const { conversationId, userId, lastReadSequenceId, readAt } = receiptData;

            console.log(`Processing read receipt for conversation ${conversationId}, seq ${lastReadSequenceId}`);

            // Update database
            await db.query(`
              UPDATE chats
              SET read_at = $1, seen = true
              WHERE conversation_id = $2
              AND sequence_id <= $3
              AND receiver_id = $4
              AND read_at IS NULL
            `, [readAt, conversationId, lastReadSequenceId, userId]);

            // Notify sender
            const [user1, user2] = conversationId.split('_');
            const senderUserId = user1 === userId ? user2 : user1;

            const senderSocketId = await redis.get(`user_socket:${senderUserId}`);

            if (senderSocketId) {
              io.to(senderSocketId).emit('readReceipt', {
                conversationId,
                readBy: userId,
                lastReadSequenceId,
                readAt
              });
            }

            // Invalidate cache
            await redis.del(`unread_count:${userId}`);

          } catch (error) {
            console.error('Error processing read receipt:', error);
          }
        }
      });

      console.log('✅ Receipt consumer connected and subscribed to read-receipts');
    } catch (error) {
      console.error('❌ Failed to setup receipt consumer:', error);
    }
  })();

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

// Helper: Queue offline messages (same pattern as friend notifications)
async function queueOfflineMessage(userId, messageData) {
  try {
    await redis.lpush(`offline_messages:${userId}`, JSON.stringify(messageData));
    await redis.ltrim(`offline_messages:${userId}`, 0, 499); // Keep last 500
    await redis.expire(`offline_messages:${userId}`, 604800); // 7 days
    console.log(`📭 Queued offline message for user ${userId}`);
  } catch (error) {
    console.error(`Error queuing offline message:`, error);
  }
}
