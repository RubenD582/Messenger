const path = require("path");
const dotenv = require("dotenv");
dotenv.config(); // Moved to the very top

const express = require("express");
const http = require("http");
const socketIo = require("socket.io");
const cors = require("cors");
const helmet = require("helmet");
const authRoutes = require("./routes/authentication");
const chatSocket = require("./sockets/chatSocket");
const friendRoutes = require("./routes/friends");
const messageRoutes = require("./routes/messages");
const statusRoutes = require("./routes/statuses"); // Import status routes
const friendSocket = require("./sockets/friendSocket"); // Import the new friend socket
const statusSocket = require("./sockets/statusSocket"); // Import status socket
const webhookRoutes = require("./routes/webhooks"); // Import webhook routes for Clerk
const suggestionsRoutes = require('./routes/suggestions'); // Import suggestions route
const notificationRoutes = require('./routes/notifications'); // Import notification routes
const debugRoutes = require('./routes/debug'); // Import debug routes
const dashboardRoutes = require('./routes/dashboard'); // Import dashboard routes
const { runNotificationService } = require('./services/notificationService'); // Import notification service
const { runChatMessageService } = require('./services/chatMessageService'); // Import chat message service
const db = require("./db");
const cookieParser = require("cookie-parser");
const { connectKafka, consumer, producer } = require('./kafkaClient'); // Add producer here

const app = express();
const server = http.createServer(app);

// Use CORS with specific configuration (for example, for Flutter apps or specific domains)
const corsOptions = {
  origin: process.env.FRONTEND_URL || "*",
  methods: ["GET", "POST"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true, // Enable credentials if you're using cookies or JWT tokens
};

// Initialize socket.io with secure CORS settings for WebSocket
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
    credentials: true,
  },
  transports: ["websocket"],
});

// IMPORTANT: Register webhook routes BEFORE body parser middleware
// Webhooks need raw body for signature verification
app.use("/webhooks", webhookRoutes);

app.use(express.json());
app.use(cors(corsOptions));
// Disable helmet for admin routes
app.use((req, res, next) => {
  if (req.path.startsWith('/admin')) {
    return next();
  }
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "http://localhost:3000", "https://localhost:3000"],
      },
    },
  })(req, res, next);
});
app.use(cookieParser());

// Routes
app.use("/auth", authRoutes);
app.use("/friends", friendRoutes);
app.use("/messages", messageRoutes);
app.use("/statuses", statusRoutes); // Use status routes
app.use("/suggestions", suggestionsRoutes); // Use suggestions route
app.use("/notifications", notificationRoutes); // Use notification routes
app.use("/debug", debugRoutes); // Use debug routes (production: disable or protect with admin auth)
app.use("/dashboard", dashboardRoutes); // Use dashboard routes

// Dashboard page route (MUST be before static files)
app.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'public/dashboard.html'));
});

// Serve dashboard static files
app.use('/admin', express.static(path.join(__dirname, 'public')));

// Serve static files from the Flutter web build directory
app.use(express.static(path.join(__dirname, '../client/build/web')));

// For any other GET request that's NOT an API or admin route, serve the Flutter app
app.get('*', (req, res) => {
  // Don't catch API routes or admin routes
  if (req.path.startsWith('/api') ||
      req.path.startsWith('/admin') ||
      req.path.startsWith('/dashboard') ||
      req.path.startsWith('/debug')) {
    return res.status(404).json({ error: 'Not found' });
  }
  res.sendFile(path.join(__dirname, '../client/build/web/index.html'));
});

// Initialize WebSockets
chatSocket(io);
friendSocket(io);
statusSocket(io);

const graphService = require('./services/graphService'); // Import graphService

// Kafka and Graph Database Connection and Subscription
(async () => {
  try {
    // Subscribe to topics BEFORE connecting consumers
    await consumer.subscribe({
      topic: 'friend-events',
      fromBeginning: false
    });
    console.log('Kafka consumer subscribed to friend-events');

    // Subscribe notification consumer BEFORE connecting
    const { notificationConsumer, messageConsumer, typingConsumer, receiptConsumer } = require('./kafkaClient');
    await notificationConsumer.subscribe({
      topic: 'notification-creation-jobs',
      fromBeginning: false
    });
    console.log('Notification consumer subscribed to notification-creation-jobs');

    // Subscribe chat message consumers BEFORE connecting
    await messageConsumer.subscribe({
      topic: 'chat-messages',
      fromBeginning: false
    });
    console.log('Message consumer subscribed to chat-messages');

    await typingConsumer.subscribe({
      topic: 'typing-indicators',
      fromBeginning: false
    });
    console.log('Typing consumer subscribed to typing-indicators');

    await receiptConsumer.subscribe({
      topic: 'read-receipts',
      fromBeginning: false
    });
    console.log('Receipt consumer subscribed to read-receipts');

    // Now, connect all Kafka clients
    await connectKafka();
    console.log('All Kafka clients connected');

    // Connect to RedisGraph
    await graphService.connectToGraph();
    console.log('Graph database connected.');

    // Start notification service consumer (just runs the consumer, already subscribed)
    await runNotificationService(io);
    console.log('Notification service consumer started.');

    // Start chat message service consumers (already subscribed)
    await runChatMessageService(io);
    console.log('Chat message service started.');

  } catch (error) {
    console.error('Failed to connect to services:', error);
    process.exit(1); // Exit if any essential service connection fails
  }
})();

// Graceful Shutdown
process.on('SIGTERM', async () => {
  try {
    await producer.disconnect();
    await consumer.disconnect();
    console.log('Kafka connections closed');
    process.exit(0);
  } catch (error) {
    console.error('Error during shutdown:', error);
    process.exit(1);
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ message: "Something went wrong!" });
});

// Start Server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}/`));

module.exports.io = io;