/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.createTable('chats', function(table) {
    table.increments('id').primary();
    // Use UUID type for sender_id and receiver_id to match the 'users' table
    table.uuid('sender_id').references('id').inTable('users').onDelete('CASCADE');
    table.uuid('receiver_id').references('id').inTable('users').onDelete('CASCADE');
    table.text('message').notNullable();
    table.boolean('seen').defaultTo(false);
    table.timestamp('timestamp').defaultTo(knex.fn.now());
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('chats');
};
