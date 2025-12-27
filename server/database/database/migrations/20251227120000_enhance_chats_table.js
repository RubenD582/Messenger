/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.table('chats', function(table) {
    // Message sequencing for ordering per conversation
    table.bigInteger('sequence_id').notNullable().defaultTo(0);

    // Kafka metadata
    table.string('kafka_partition').nullable();
    table.bigInteger('kafka_offset').nullable();

    // Read receipts
    table.timestamp('delivered_at').nullable();
    table.timestamp('read_at').nullable();

    // Message metadata
    table.uuid('message_id').notNullable(); // UUID for the message
    table.text('conversation_id').notNullable(); // Format: "uuid1_uuid2" (sorted)
    table.string('message_type').defaultTo('text'); // text, image, file, etc.
    table.jsonb('metadata').nullable(); // For attachments, reactions, etc.

    // Soft delete
    table.timestamp('deleted_at').nullable();
    table.uuid('deleted_by').nullable();

    // Versioning for conflict resolution
    table.bigInteger('version').defaultTo(knex.raw('EXTRACT(EPOCH FROM NOW())::BIGINT'));

    // Performance indexes
    table.index(['conversation_id', 'sequence_id'], 'idx_conversation_sequence');
    table.index(['receiver_id', 'read_at'], 'idx_unread_messages');
    table.index(['sender_id', 'receiver_id', 'timestamp'], 'idx_chat_timeline');
    table.index('kafka_offset', 'idx_kafka_offset');

    // Composite unique constraint for idempotency
    table.unique(['conversation_id', 'sequence_id'], {indexName: 'unique_conversation_message'});
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.table('chats', function(table) {
    // Drop indexes first
    table.dropIndex(['conversation_id', 'sequence_id'], 'idx_conversation_sequence');
    table.dropIndex(['receiver_id', 'read_at'], 'idx_unread_messages');
    table.dropIndex(['sender_id', 'receiver_id', 'timestamp'], 'idx_chat_timeline');
    table.dropIndex('kafka_offset', 'idx_kafka_offset');
    table.dropUnique(['conversation_id', 'sequence_id'], 'unique_conversation_message');

    // Drop columns
    table.dropColumn('sequence_id');
    table.dropColumn('kafka_partition');
    table.dropColumn('kafka_offset');
    table.dropColumn('delivered_at');
    table.dropColumn('read_at');
    table.dropColumn('message_id');
    table.dropColumn('conversation_id');
    table.dropColumn('message_type');
    table.dropColumn('metadata');
    table.dropColumn('deleted_at');
    table.dropColumn('deleted_by');
    table.dropColumn('version');
  });
};
