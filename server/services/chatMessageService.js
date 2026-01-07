// chatMessageService.js - Kafka consumers for chat messages
const { messageConsumer, typingConsumer, receiptConsumer } = require('../kafkaClient');
const db = require('../db');
const redis = require('../config/redisClient');
const reliabilityService = require('./messageReliabilityService');
const dashboardService = require('./dashboardService');

let ioInstance = null;

// Initialize the service with the socket.io instance
async function runChatMessageService(io) {
  ioInstance = io;

  // Start all three consumers
  await startMessageConsumer();
  await startTypingConsumer();
  await startReceiptConsumer();

  console.log('✅ Chat message service started (all 3 consumers running)');
}

// CONSUMER 1: Chat Messages
async function startMessageConsumer() {
  await messageConsumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const messageData = JSON.parse(message.value.toString());
        const { messageId, senderId, receiverId, conversationId, sequenceId } = messageData;

        console.log(`Processing message ${messageId} in conversation ${conversationId}`);

        // Store in database with idempotency
        const insertResult = await db.query(`
          INSERT INTO chats (
            message_id, sender_id, receiver_id, message, seen, timestamp,
            sequence_id, conversation_id, message_type, metadata,
            kafka_partition, kafka_offset, version,
            position_x, position_y, is_positioned
          ) VALUES ($1, $2, $3, $4, false, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
          ON CONFLICT (conversation_id, sequence_id) DO NOTHING
          RETURNING message_id
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

        if (insertResult.rows.length > 0) {
          console.log(`💾 Message saved to database: ${messageId}`);

          // Track message sent in reliability service
          if (!messageData.isRetry) {
            await reliabilityService.trackMessageSent(messageId, conversationId, receiverId);
          }

          // Track in dashboard
          await dashboardService.trackMessageSent();
        } else {
          console.log(`⚠️  Message skipped (duplicate): ${messageId}`);
        }

        // Get socket IDs from Redis
        const senderSocketId = await redis.get(`user_socket:${senderId}`);
        const receiverSocketId = await redis.get(`user_socket:${receiverId}`);

        console.log(`📤 Emitting message ${messageId}:`);
        console.log(`   Sender: ${senderId} → Socket: ${senderSocketId || 'NOT FOUND'}`);
        console.log(`   Receiver: ${receiverId} → Socket: ${receiverSocketId || 'NOT FOUND'}`);

        // Emit to both sender and receiver
        if (senderSocketId) {
          ioInstance.to(senderSocketId).emit('newMessage', messageData);
          console.log(`   ✅ Emitted to sender socket ${senderSocketId}`);
        } else {
          console.log(`   ❌ Sender socket not found - user may be offline`);
        }

        if (receiverSocketId) {
          ioInstance.to(receiverSocketId).emit('newMessage', messageData);
          console.log(`   ✅ Emitted to receiver socket ${receiverSocketId}`);
          // Invalidate unread count cache
          await redis.del(`unread_count:${receiverId}`);

          // Track delivered in dashboard
          await dashboardService.trackMessageDelivered();
        } else {
          console.log(`   ❌ Receiver socket not found - queuing offline`);
          // Queue for offline delivery
          await queueOfflineMessage(receiverId, messageData);

          // Track failed delivery in dashboard
          await dashboardService.trackMessageFailed();

          // Schedule retry for offline messages
          setTimeout(async () => {
            await reliabilityService.retryMessage(messageId);
          }, 5000); // Retry after 5 seconds
        }

      } catch (error) {
        console.error('Error processing chat message:', error);
        await dashboardService.logError(error, {
          service: 'chatMessageService',
          consumer: 'messageConsumer',
          messageId: messageData?.messageId,
        });
      }
    }
  });

  console.log('✅ Message consumer started');
}

// CONSUMER 2: Typing Indicators
async function startTypingConsumer() {
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
          ioInstance.to(otherSocketId).emit('typingIndicator', {
            conversationId,
            userId,
            isTyping,
            timestamp: typingData.timestamp
          });
        }

      } catch (error) {
        console.error('Error processing typing indicator:', error);
        await dashboardService.logError(error, {
          service: 'chatMessageService',
          consumer: 'typingConsumer',
        });
      }
    }
  });

  console.log('✅ Typing consumer started');
}

// CONSUMER 3: Read Receipts
async function startReceiptConsumer() {
  await receiptConsumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const receiptData = JSON.parse(message.value.toString());
        const { conversationId, userId, lastReadSequenceId, readAt } = receiptData;

        console.log(`Processing read receipt for conversation ${conversationId}, seq ${lastReadSequenceId}`);

        // Update database and get message IDs
        const result = await db.query(`
          UPDATE chats
          SET read_at = $1, seen = true
          WHERE conversation_id = $2
          AND sequence_id <= $3
          AND receiver_id = $4
          AND read_at IS NULL
          RETURNING message_id
        `, [readAt, conversationId, lastReadSequenceId, userId]);

        // Mark each message as read in reliability service
        for (const row of result.rows) {
          await reliabilityService.markRead(row.message_id, userId);
        }

        if (result.rows.length > 0) {
          console.log(`✅ Marked ${result.rows.length} messages as read`);
        }

        // Notify sender
        const [user1, user2] = conversationId.split('_');
        const senderUserId = user1 === userId ? user2 : user1;

        const senderSocketId = await redis.get(`user_socket:${senderUserId}`);

        if (senderSocketId) {
          ioInstance.to(senderSocketId).emit('readReceipt', {
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
        await dashboardService.logError(error, {
          service: 'chatMessageService',
          consumer: 'receiptConsumer',
        });
      }
    }
  });

  console.log('✅ Receipt consumer started');
}

// Helper: Queue offline messages
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

module.exports = { runChatMessageService };
