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
const db = require("./db");
const dotenv = require("dotenv");
const cookieParser = require("cookie-parser");
const { connectKafka, consumer, producer } = require('./kafkaClient'); // Add producer here

// Load environment variables
dotenv.config();

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

app.use(express.json());
app.use(cors(corsOptions));
app.use(helmet());
app.use(cookieParser());

// Routes
app.use("/auth", authRoutes);
app.use("/friends", friendRoutes);
app.use("/messages", messageRoutes);

// Initialize WebSockets
chatSocket(io);
friendSocket(io);

// Kafka Connection and Subscription
(async () => {
  try {
    await connectKafka();
    
    // Subscribe to topics here if needed
    await consumer.subscribe({ 
      topic: 'friend-events', 
      fromBeginning: false 
    });
    
    console.log('Kafka connected and subscribed to friend-events');
  } catch (error) {
    console.error('Failed to connect to Kafka:', error);
    process.exit(1); // Exit if Kafka connection fails
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