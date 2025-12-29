/**
 * Migration: Add position fields for interactive message positioning
 * Allows messages to be dragged and positioned anywhere on canvas
 */

exports.up = function(knex) {
  return knex.schema.table('chats', function(table) {
    // Position coordinates (null = normal flow, 0.0-1.0 = positioned as percentage)
    table.decimal('position_x', 5, 4).nullable();  // e.g., 0.5432 (54.32% from left)
    table.decimal('position_y', 5, 4).nullable();  // e.g., 0.7654 (76.54% from top)

    // Whether message is manually positioned or in normal flow
    table.boolean('is_positioned').defaultTo(false);

    // Track who positioned the message
    table.string('positioned_by').nullable();

    // When the message was positioned
    table.timestamp('positioned_at').nullable();

    // Add index for querying positioned messages
    table.index(['conversation_id', 'is_positioned']);
  });
};

exports.down = function(knex) {
  return knex.schema.table('chats', function(table) {
    table.dropColumn('position_x');
    table.dropColumn('position_y');
    table.dropColumn('is_positioned');
    table.dropColumn('positioned_by');
    table.dropColumn('positioned_at');
    table.dropIndex(['conversation_id', 'is_positioned']);
  });
};
