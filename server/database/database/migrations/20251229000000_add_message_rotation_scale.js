/**
 * Migration: Add rotation and scale fields for message transformations
 * Allows messages to be rotated and scaled interactively
 */

exports.up = function(knex) {
  return knex.schema.table('chats', function(table) {
    // Rotation in radians (null = 0, no rotation)
    table.decimal('rotation', 8, 6).nullable();

    // Scale factor (null = 1.0, normal size)
    table.decimal('scale', 5, 3).nullable();
  });
};

exports.down = function(knex) {
  return knex.schema.table('chats', function(table) {
    table.dropColumn('rotation');
    table.dropColumn('scale');
  });
};
