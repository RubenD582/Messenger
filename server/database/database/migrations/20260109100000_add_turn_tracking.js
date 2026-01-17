/**
 * Migration: Add turn-based tracking to remix system
 *
 * Adds fields to track whose turn it is, turn order, and contributors
 */

exports.up = async function(knex) {
  // Add turn tracking fields to remix_posts
  await knex.schema.table('remix_posts', (table) => {
    table.uuid('current_turn_user_id'); // Whose turn it is currently
    table.jsonb('turn_order').defaultTo('[]'); // Array of user IDs in turn order
    table.jsonb('contributors').defaultTo('[]'); // Array of user IDs who have contributed this round
    table.integer('turn_count').defaultTo(0); // Total number of turns taken
    table.integer('max_turns'); // Maximum turns (equal to number of members)

    // Foreign key for current turn user
    table.foreign('current_turn_user_id').references('id').inTable('users').onDelete('SET NULL');

    // Index for current turn queries
    table.index('current_turn_user_id');
  });

  // Add turn tracking fields to remix_group_members
  await knex.schema.table('remix_group_members', (table) => {
    table.integer('turn_position').defaultTo(0); // Position in turn order (0-indexed)
  });

  console.log('✅ Added turn tracking fields to remix tables');
};

exports.down = async function(knex) {
  // Remove turn tracking fields from remix_posts
  await knex.schema.table('remix_posts', (table) => {
    table.dropForeign('current_turn_user_id');
    table.dropColumn('current_turn_user_id');
    table.dropColumn('turn_order');
    table.dropColumn('contributors');
    table.dropColumn('turn_count');
    table.dropColumn('max_turns');
  });

  // Remove turn position from remix_group_members
  await knex.schema.table('remix_group_members', (table) => {
    table.dropColumn('turn_position');
  });

  console.log('✅ Removed turn tracking fields from remix tables');
};
