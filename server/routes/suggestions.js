// server/routes/suggestions.js
const express = require('express');
const router = express.Router();
const graphService = require('../services/graphService');
const { authMiddleware } = require('../middleware/authMiddleware'); // Assuming you have an auth middleware

// GET /api/suggestions/:userId
// Returns a list of suggested friends for the given userId
router.get('/:userId', authMiddleware, async (req, res) => {
    const { userId } = req.params;
    try {
        const suggestions = await graphService.getFriendSuggestions(userId);
        res.json(suggestions);
    } catch (error) {
        console.error('Error fetching friend suggestions:', error);
        res.status(500).json({ message: 'Error fetching friend suggestions.' });
    }
});

module.exports = router;