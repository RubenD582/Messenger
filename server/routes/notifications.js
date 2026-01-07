// server/routes/notifications.js
const express = require("express");
const router = express.Router();
const { authenticateToken } = require("../middleware/authMiddleware");
const redis = require('../config/redisClient');

// GET /notifications
// Fetches the user's most recent notifications from Redis.
router.get("/", authenticateToken, async (req, res) => {
    const userId = req.user.userId;
    const redisKey = `notifications:${userId}`;

    try {
        // Fetch the list of notifications. LRANGE gets a range of elements from a list.
        // 0 is the start, 99 is the end. This gets the top 100 notifications.
        const notificationStrings = await redis.lrange(redisKey, 0, 99);

        if (!notificationStrings) {
            return res.json({ notifications: [] });
        }

        // The notifications are stored as JSON strings, so we need to parse them.
        const notifications = notificationStrings.map(n => JSON.parse(n));

        // Filter out notifications older than 30 days
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
        const validNotifications = notifications.filter(n => n.timestamp > thirtyDaysAgo);

        res.json({ notifications: validNotifications });

    } catch (error) {
        console.error(`Error fetching notifications for user ${userId}:`, error);
        res.status(500).json({ message: "Server error" });
    }
});

// POST /notifications/mark-read
// Marks all of the user's notifications as read.
router.post("/mark-read", authenticateToken, async (req, res) => {
    const userId = req.user.userId;
    const redisKey = `notifications:${userId}`;

    try {
        // Fetch all notifications
        const notificationStrings = await redis.lrange(redisKey, 0, -1);
        if (!notificationStrings || notificationStrings.length === 0) {
            return res.status(200).json({ message: "No notifications to mark as read." });
        }

        // Update the 'read' flag on each notification object
        const updatedNotifications = notificationStrings.map(n => {
            const notification = JSON.parse(n);
            notification.read = true;
            return JSON.stringify(notification);
        });

        // Atomically replace the entire list with the updated list
        const multi = redis.multi();
        multi.del(redisKey);
        multi.rpush(redisKey, ...updatedNotifications);
        await multi.exec();

        res.status(200).json({ message: "Notifications marked as read." });

    } catch (error) {
        console.error(`Error marking notifications as read for user ${userId}:`, error);
        res.status(500).json({ message: "Server error" });
    }
});

// POST /notifications/update-status
// Updates the status of a notification (e.g., when accepting/rejecting)
router.post("/update-status", authenticateToken, async (req, res) => {
    const userId = req.user.userId;
    const { notificationId, status } = req.body; // status: 'accepted', 'rejected'
    const redisKey = `notifications:${userId}`;

    try {
        // Fetch all notifications
        const notificationStrings = await redis.lrange(redisKey, 0, -1);
        if (!notificationStrings || notificationStrings.length === 0) {
            return res.status(404).json({ message: "Notification not found." });
        }

        // Find and update the specific notification
        let found = false;
        const updatedNotifications = notificationStrings.map(n => {
            const notification = JSON.parse(n);
            if (notification.id === notificationId) {
                notification.status = status;
                notification.updatedAt = new Date().toISOString();
                found = true;
            }
            return JSON.stringify(notification);
        });

        if (!found) {
            return res.status(404).json({ message: "Notification not found." });
        }

        // Atomically replace the entire list with the updated list
        const multi = redis.multi();
        multi.del(redisKey);
        multi.rpush(redisKey, ...updatedNotifications);
        await multi.exec();

        res.status(200).json({ message: "Notification status updated." });

    } catch (error) {
        console.error(`Error updating notification status for user ${userId}:`, error);
        res.status(500).json({ message: "Server error" });
    }
});


module.exports = router;
