const db = require("../db");

module.exports = (io) => {
  io.on("connection", (socket) => {
    console.log(`User connected: ${socket.id}`);

    // Join a private room for the user (based on their user ID)
    socket.on("joinRoom", ({ userId }) => {
      socket.join(`user_${userId}`);
      console.log(`User ${userId} joined room: user_${userId}`);
    });

    // Handle Sending Messages
    socket.on("sendMessage", async (data) => {
      const { senderId, receiverId, message } = data;

      if (!message.trim()) return;

      try {
        // Store message in the database
        const result = await db.query(
          "INSERT INTO chats (sender_id, receiver_id, message, seen) VALUES ($1, $2, $3, false) RETURNING *",
          [senderId, receiverId, message]
        );

        const savedMessage = result.rows[0];

        // Emit message to sender and receiver
        io.to(`user_${receiverId}`).emit("receiveMessage", savedMessage);
        io.to(`user_${senderId}`).emit("receiveMessage", savedMessage);
      } catch (error) {
        console.error("Error sending message:", error);
        socket.emit("error", { message: "Failed to send message." });
      }
    });

    // Handle Marking Messages as Seen
    socket.on("markAsSeen", async ({ senderId, receiverId }) => {
      try {
        await db.query(
          "UPDATE chats SET seen = true WHERE sender_id = $1 AND receiver_id = $2",
          [senderId, receiverId]
        );

        // Notify sender that their messages were seen
        io.to(`user_${senderId}`).emit("messagesSeen", { senderId, receiverId });
      } catch (error) {
        console.error("Error marking messages as seen:", error);
        socket.emit("error", { message: "Failed to mark messages as seen." });
      }
    });

    // Handle User Disconnect
    socket.on("disconnect", () => {
      console.log(`User disconnected: ${socket.id}`);
    });
  });
};
