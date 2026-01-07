// dashboard.js - Dashboard API endpoints
const express = require('express');
const router = express.Router();
const dashboardService = require('../services/dashboardService');
const { authenticateToken } = require('../middleware/authMiddleware');

// GET /dashboard/data - Get all dashboard data
router.get('/data', authenticateToken, async (req, res) => {
  try {
    const data = await dashboardService.getDashboardData();
    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error getting dashboard data:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get dashboard data',
      error: error.message,
    });
  }
});

// GET /dashboard/metrics - Get current metrics only
router.get('/metrics', authenticateToken, async (req, res) => {
  try {
    const metrics = await dashboardService.getCurrentMetrics();
    res.json({
      success: true,
      metrics,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to get metrics',
      error: error.message,
    });
  }
});

// GET /dashboard/errors - Get error statistics
router.get('/errors', authenticateToken, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 100;
    const [stats, recent] = await Promise.all([
      dashboardService.getErrorStats(),
      dashboardService.getRecentErrors(limit),
    ]);

    res.json({
      success: true,
      stats,
      recent,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to get errors',
      error: error.message,
    });
  }
});

// GET /dashboard/hourly - Get hourly statistics
router.get('/hourly', authenticateToken, async (req, res) => {
  try {
    const hours = parseInt(req.query.hours) || 24;
    const stats = await dashboardService.getHourlyStats(hours);

    res.json({
      success: true,
      stats,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to get hourly stats',
      error: error.message,
    });
  }
});

// GET /dashboard/daily - Get daily statistics
router.get('/daily', authenticateToken, async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 7;
    const stats = await dashboardService.getDailyStats(days);

    res.json({
      success: true,
      stats,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to get daily stats',
      error: error.message,
    });
  }
});

module.exports = router;
