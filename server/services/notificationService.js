// server/services/notificationService.js
const { notificationConsumer } = require('../kafkaClient');
const redis = require('../config/redisClient');
const { v4: uuidv4 } = require('uuid');

const NOTIFICATION_JOBS_TOPIC = 'notification-creation-jobs';
const NOTIFICATIONS_LIMIT = 100; // Keep the last 100 notifications per user

let ioInstance; // To hold the Socket.IO instance

const run = async (io) => {
    ioInstance = io; // Store the io instance

    console.log('[NotificationService] Starting consumer run loop...');

    await notificationConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            try {
                const event = JSON.parse(message.value.toString());
                console.log(`[NotificationService] ✉️  Received event: ${event.type} for user ${event.payload?.recipientId}`);

                await processNotificationEvent(event);

            } catch (error) {
                console.error('[NotificationService] Error processing message:', error);
            }
        },
    });
};

const processNotificationEvent = async (event) => {
    const { type, payload } = event;
    let recipientId;
    let notification;
    let badgeCountUpdate = null;

    const notificationId = uuidv4();
    const timestamp = new Date().toISOString();

    switch (type) {
        case 'FRIEND_REQUEST_RECEIVED':
            recipientId = payload.recipientId;

            // Check for duplicate notification
            const isDuplicateRequest = await checkDuplicateNotification(
                recipientId,
                'FRIEND_REQUEST_RECEIVED',
                payload.senderId
            );
            if (isDuplicateRequest) {
                console.log(`[NotificationService] Duplicate FRIEND_REQUEST_RECEIVED notification skipped`);
                // Still update badge count
                await emitBadgeCountUpdate(recipientId, payload.requestCount);
                return;
            }

            notification = {
                id: notificationId,
                type: 'FRIEND_REQUEST_RECEIVED',
                actor: {
                    id: payload.senderId,
                    username: payload.senderUsername,
                    verified: payload.senderVerified || false,
                    developer: payload.senderDeveloper || false,
                },
                read: false,
                status: 'pending', // pending, accepted, rejected
                timestamp: timestamp,
            };
            badgeCountUpdate = payload.requestCount;
            break;

        case 'FRIEND_REQUEST_ACCEPTED':
            recipientId = payload.recipientId;

            // Check for duplicate notification
            const isDuplicateAccept = await checkDuplicateNotification(
                recipientId,
                'FRIEND_REQUEST_ACCEPTED',
                payload.acceptorId
            );
            if (isDuplicateAccept) {
                console.log(`[NotificationService] Duplicate FRIEND_REQUEST_ACCEPTED notification skipped`);
                // Still update badge count
                await emitBadgeCountUpdate(recipientId, payload.requestCount);
                return;
            }

            notification = {
                id: notificationId,
                type: 'FRIEND_REQUEST_ACCEPTED',
                actor: {
                    id: payload.acceptorId,
                    username: payload.acceptorUsername,
                    verified: payload.acceptorVerified || false,
                    developer: payload.acceptorDeveloper || false,
                },
                read: false,
                status: 'completed', // This is informational, not actionable
                timestamp: timestamp,
            };
            badgeCountUpdate = payload.requestCount;
            break;

        case 'BADGE_COUNT_UPDATE':
            // Only update badge count, no notification
            recipientId = payload.recipientId;
            await emitBadgeCountUpdate(recipientId, payload.requestCount);
            return;

        default:
            console.warn(`[NotificationService] Unknown event type: ${type}`);
            return;
    }

    if (recipientId && notification) {
        await saveNotification(recipientId, notification, badgeCountUpdate);
    }
};

const saveNotification = async (userId, notification, badgeCount = null) => {
    try {
        const redisKey = `notifications:${userId}`;
        const notificationString = JSON.stringify(notification);

        // Use Redis pipeline for atomic operations
        const pipeline = redis.pipeline();

        // LPUSH the new notification to the user's list
        pipeline.lpush(redisKey, notificationString);

        // Trim the list to keep only the latest N notifications
        pipeline.ltrim(redisKey, 0, NOTIFICATIONS_LIMIT - 1);

        // Set expiry on notifications list (30 days)
        pipeline.expire(redisKey, 2592000);

        // Track this notification to prevent duplicates (1 hour TTL)
        const dedupeKey = `notif_dedup:${userId}:${notification.type}:${notification.actor.id}`;
        pipeline.setex(dedupeKey, 3600, notification.id);

        await pipeline.exec();

        console.log(`[NotificationService] ✅ Saved notification for user ${userId}:`, notification.type);

        // Emit WebSocket event to the specific user's room
        if (ioInstance) {
            const socketsInRoom = await ioInstance.in(userId).fetchSockets();
            console.log(`[NotificationService] 🔌 User ${userId} has ${socketsInRoom.length} active socket(s)`);

            ioInstance.to(userId).emit('newUserNotification', notification);
            console.log(`[NotificationService] 📤 Emitted newUserNotification to user ${userId}`);

            // Also emit badge count update if provided
            if (badgeCount !== null) {
                await emitBadgeCountUpdate(userId, badgeCount);
            }
        }

    } catch (error) {
        console.error(`[NotificationService] Error saving notification to Redis for user ${userId}:`, error);
    }
};

const checkDuplicateNotification = async (userId, type, actorId) => {
    try {
        const dedupeKey = `notif_dedup:${userId}:${type}:${actorId}`;
        const exists = await redis.exists(dedupeKey);
        return exists === 1;
    } catch (error) {
        console.error(`[NotificationService] Error checking duplicate:`, error);
        return false; // On error, allow the notification
    }
};

const emitBadgeCountUpdate = async (userId, requestCount) => {
    try {
        if (ioInstance) {
            ioInstance.to(userId).emit('badgeCountUpdate', {
                count: parseInt(requestCount) || 0
            });
            console.log(`[NotificationService] 🔢 Emitted badge count update to user ${userId}: ${requestCount}`);
        }
    } catch (error) {
        console.error(`[NotificationService] ❌ Error emitting badge count:`, error);
    }
};


module.exports = {
    runNotificationService: run,
    notificationConsumer // Exporting for centralized connection management
};
