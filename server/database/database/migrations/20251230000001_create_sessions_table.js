/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.createTable('user_sessions', function(table) {
    // Primary key
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));

    // Foreign key to users table
    table.uuid('user_id').notNullable();
    table.foreign('user_id').references('users.id').onDelete('CASCADE');

    // Clerk session identifier
    table.string('clerk_session_id').notNullable().unique();

    // Device information
    table.string('device_type').nullable(); // e.g., "mobile", "desktop", "tablet"
    table.string('device_name').nullable(); // e.g., "iPhone 13", "Chrome on macOS"
    table.string('user_agent').nullable(); // Full user agent string

    // Network information
    table.string('ip_address').nullable();

    // Session timestamps
    table.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    table.timestamp('last_active').notNullable().defaultTo(knex.fn.now());
    table.timestamp('expires_at').nullable();

    // Session status
    table.boolean('is_active').notNullable().defaultTo(true);
    table.timestamp('revoked_at').nullable();

    // Performance indexes
    table.index('user_id', 'idx_session_user_id');
    table.index('clerk_session_id', 'idx_session_clerk_id');
    table.index(['user_id', 'is_active'], 'idx_active_user_sessions');
    table.index('last_active', 'idx_session_last_active');
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('user_sessions');
};
