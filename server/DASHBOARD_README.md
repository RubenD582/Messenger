# Messenger System Dashboard

A comprehensive real-time monitoring dashboard for tracking system health, message delivery, and errors.

## Features

### Real-Time Metrics
- **Active Connections**: Number of users currently connected via WebSocket
- **Messages (Last Hour)**: Recent messaging activity
- **Total Messages**: Lifetime message count
- **Total Users**: Total registered users
- **Delivery Rate**: Percentage of successfully delivered messages
- **Failed Messages (DLQ)**: Messages in dead letter queue

### Time-Series Charts
- **Message Delivery Chart**: Hourly breakdown of sent, delivered, and failed messages (last 24 hours)
- **Errors Over Time**: Hourly error counts (last 24 hours)

### Error Monitoring
- **Critical Errors**: Connection failures, timeouts
- **Errors**: General application errors
- **Warnings**: Validation errors, non-critical issues
- **Recent Errors List**: Detailed error logs with stack traces and context

### Dashboard Data Tracking
The system automatically tracks:
- Message sent/delivered/failed events
- Error occurrences with severity categorization
- Hourly statistics (kept for 7 days)
- Daily statistics (kept for 30 days)

## Accessing the Dashboard

### URL
```
http://localhost:3000/admin/dashboard
```

### Authentication
Login with any valid user credentials from your messenger app.

## API Endpoints

All endpoints require authentication (`Authorization: Bearer <token>`):

### Dashboard Data
- `GET /dashboard/data` - Get comprehensive dashboard data
- `GET /dashboard/metrics` - Get current metrics only
- `GET /dashboard/errors?limit=100` - Get error statistics and recent errors
- `GET /dashboard/hourly?hours=24` - Get hourly statistics
- `GET /dashboard/daily?days=7` - Get daily statistics

### Example Response
```json
{
  "success": true,
  "data": {
    "current": {
      "activeConnections": 5,
      "totalMessages": 1234,
      "totalUsers": 50,
      "messagesLastHour": 23,
      "reliability": {
        "lastHour": {
          "sent": 23,
          "delivered": 22,
          "failed": 1,
          "dlqSize": 0
        },
        "rates": {
          "deliveryRate": "95.65%",
          "readRate": "80.00%"
        }
      }
    },
    "errors": {
      "stats": {
        "total24h": 5,
        "lastHour": 2,
        "bySeverity": {
          "critical": 1,
          "error": 3,
          "warning": 1
        }
      },
      "recent": [...]
    },
    "timeSeries": {
      "hourly": [...],
      "daily": [...]
    }
  }
}
```

## Dashboard Service

### Tracking Methods

#### Message Tracking
```javascript
const dashboardService = require('./services/dashboardService');

// Track message sent
await dashboardService.trackMessageSent();

// Track message delivered
await dashboardService.trackMessageDelivered();

// Track message failed
await dashboardService.trackMessageFailed();
```

#### Error Tracking
```javascript
// Log an error
try {
  // ... your code
} catch (error) {
  await dashboardService.logError(error, {
    service: 'serviceName',
    consumer: 'consumerName',
    additionalContext: 'value'
  });
}
```

### Error Severity Levels
- **critical**: Connection failures, timeouts (e.g., ECONNREFUSED)
- **error**: General application errors
- **warning**: Validation errors, required field errors

## Data Retention

- **Hourly Stats**: 7 days
- **Daily Stats**: 30 days
- **Error Logs**: Last 1000 errors
- **DLQ Messages**: Last 10000 entries

## Auto-Refresh

The dashboard automatically refreshes every 10 seconds to show real-time data.

## Technologies Used

- **Backend**: Node.js, Express, Redis, PostgreSQL
- **Frontend**: HTML5, CSS3, Vanilla JavaScript
- **Charts**: Chart.js 4.4.0
- **Real-time Updates**: 10-second polling interval

## Production Deployment

For production use:

1. **Add Authentication Middleware**: Restrict dashboard access to admin users only
   ```javascript
   app.use("/dashboard", adminAuthMiddleware, dashboardRoutes);
   ```

2. **Enable HTTPS**: Use SSL/TLS for secure dashboard access

3. **Set Up Alerts**: Configure the alertOperations method in messageReliabilityService.js to send alerts to PagerDuty, Slack, or email

4. **Monitor Performance**: The dashboard itself is lightweight and queries are optimized with Redis caching

## Troubleshooting

### Dashboard not loading
- Check if server is running: `http://localhost:3000`
- Verify authentication token is valid
- Check browser console for errors

### No data showing
- Ensure messages are being sent through the system
- Check Redis connection
- Verify Kafka consumers are running

### Errors not appearing
- Make sure error logging is properly integrated (see chatMessageService.js for examples)
- Check Redis keys: `redis-cli KEYS "dashboard:*"`

## Example Integration

See `server/services/chatMessageService.js` for a complete example of how the dashboard service is integrated into message processing.
