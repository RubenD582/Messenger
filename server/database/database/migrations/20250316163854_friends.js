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
    
    // Enhanced status tracking
    table.enu('status', ['pending', 'accepted', 'blocked', 'deleted']).defaultTo('pending');
    
    // Timestamps
    table.timestamp('created_at').defaultTo(knex.fn.now());
    table.timestamp('updated_at').defaultTo(knex.fn.now());
    
    // Soft delete columns
    table.timestamp('deleted_at').nullable();
    table.uuid('deleted_by').nullable().references('id').inTable('users');
    table.string('deletion_reason', 100).nullable();
    
    // Versioning
    table.bigInteger('version').nullable().defaultTo(knex.raw('EXTRACT(EPOCH FROM NOW())'));
    
    // Indexes for performance
    table.index(['user_id', 'status', 'deleted_at']);
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('friends');
};