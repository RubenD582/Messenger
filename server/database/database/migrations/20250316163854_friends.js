/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.createTable('friends', function(table) {
    table.increments('id').primary();
    // Use UUID type for the foreign keys to match the 'users' table
    table.uuid('user_id').references('id').inTable('users').onDelete('CASCADE');
    table.uuid('friend_id').references('id').inTable('users').onDelete('CASCADE');
    table.enu('status', ['pending', 'accepted', 'blocked']).defaultTo('pending');
    table.timestamp('created_at').defaultTo(knex.fn.now());
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('friends');
};
