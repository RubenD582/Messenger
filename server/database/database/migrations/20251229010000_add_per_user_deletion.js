/**
 * Migration: Add per-user deletion tracking (WhatsApp-style)
 * Allows each user to independently delete conversations without affecting the other user
 */

exports.up = function(knex) {
  return knex.schema.table('chats', function(table) {
    // Track when sender deleted the message (null = not deleted by sender)
    table.timestamp('sender_deleted_at').nullable();

    // Track when receiver deleted the message (null = not deleted by receiver)
    table.timestamp('receiver_deleted_at').nullable();

    // Add index for efficient filtering
    table.index(['sender_id', 'sender_deleted_at']);
    table.index(['receiver_id', 'receiver_deleted_at']);
  });
};

exports.down = function(knex) {
  return knex.schema.table('chats', function(table) {
    table.dropIndex(['sender_id', 'sender_deleted_at']);
    table.dropIndex(['receiver_id', 'receiver_deleted_at']);
    table.dropColumn('sender_deleted_at');
    table.dropColumn('receiver_deleted_at');
  });
};
