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
const friendSocket = require("./sockets/friendSocket"); // Import the new friend socket
const webhookRoutes = require("./routes/webhooks"); // Import webhook routes for Clerk
const suggestionsRoutes = require('./routes/suggestions'); // Import suggestions route
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
app.use(helmet());
app.use(cookieParser());

// Routes
app.use("/auth", authRoutes);
app.use("/friends", friendRoutes);
app.use("/messages", messageRoutes);
app.use("/suggestions", suggestionsRoutes); // Use suggestions route

// Serve static files from the Flutter web build directory
app.use(express.static(path.join(__dirname, '../client/build/web')));

// For any other GET request, serve the Flutter app's index.html
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/build/web/index.html'));
});

// Initialize WebSockets
chatSocket(io);
friendSocket(io);

const graphService = require('./services/graphService'); // Import graphService

// Kafka and Graph Database Connection and Subscription
(async () => {
  try {
    await connectKafka();
    await graphService.connectToGraph(); // Connect to RedisGraph
    
    // Subscribe to topics here if needed
    await consumer.subscribe({ 
      topic: 'friend-events', 
      fromBeginning: false 
    });
    
    console.log('Kafka connected and subscribed to friend-events');
    console.log('Graph database connected.');
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