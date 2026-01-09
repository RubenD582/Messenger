// remixService.js - Real-time remix updates via Kafka and WebSocket
const { remixConsumer } = require('../kafkaClient');

class RemixService {
  constructor(io) {
    this.io = io;
    this.userSockets = new Map(); // userId -> socket
  }

  /**
   * Start consuming remix updates from Kafka
   */
  async start() {
    try {
      await remixConsumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const data = JSON.parse(message.value.toString());
            this.handleRemixUpdate(data);
          } catch (error) {
            console.error('Error processing remix update:', error);
          }
        },
      });

      console.log('✅ Remix service started - listening for updates');
    } catch (error) {
      console.error('❌ Error starting remix service:', error);
      throw error;
    }
  }

  /**
   * Handle remix update from Kafka
   */
  handleRemixUpdate(data) {
    const { type, groupId, post, layer, postedBy, addedBy, layerId } = data;

    console.log(`📨 Remix update: ${type} for group ${groupId}`);

    // Emit to all users in the group
    this.io.to(`remix_group_${groupId}`).emit('remix_update', {
      type,
      groupId,
      post,
      layer,
      postedBy,
      addedBy,
      layerId,
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * Register a socket connection
   */
  registerSocket(socket, userId) {
    this.userSockets.set(userId, socket);

    // Handle joining remix groups
    socket.on('join_remix_group', (groupId) => {
      socket.join(`remix_group_${groupId}`);
      console.log(`User ${userId} joined remix group ${groupId}`);
    });

    // Handle leaving remix groups
    socket.on('leave_remix_group', (groupId) => {
      socket.leave(`remix_group_${groupId}`);
      console.log(`User ${userId} left remix group ${groupId}`);
    });

    // Handle disconnect
    socket.on('disconnect', () => {
      this.userSockets.delete(userId);
      console.log(`User ${userId} disconnected from remix service`);
    });
  }
}

let remixServiceInstance = null;

/**
 * Initialize the remix service
 */
function initRemixService(io) {
  if (!remixServiceInstance) {
    remixServiceInstance = new RemixService(io);
  }
  return remixServiceInstance;
}

/**
 * Run the remix service
 */
async function runRemixService(io) {
  try {
    const service = initRemixService(io);
    await service.start();
  } catch (error) {
    console.error('❌ Failed to start remix service:', error);
    process.exit(1);
  }
}

module.exports = {
  initRemixService,
  runRemixService,
};
