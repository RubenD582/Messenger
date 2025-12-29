/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.table('users', function(table) {
    // Add Clerk user ID - unique identifier from Clerk
    // Nullable initially to allow migration of existing users
    table.string('clerk_user_id').nullable().unique();

    // Add email field for Clerk authentication
    // Nullable initially to allow migration of existing users
    table.string('email').nullable().unique();

    // Make username nullable for migration period
    // Users will authenticate via email instead of username
    table.string('username').nullable().alter();

    // Add index on clerk_user_id for fast lookups
    table.index('clerk_user_id', 'idx_clerk_user_id');

    // Add index on email for fast lookups
    table.index('email', 'idx_user_email');
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.table('users', function(table) {
    // Drop indexes first
    table.dropIndex('clerk_user_id', 'idx_clerk_user_id');
    table.dropIndex('email', 'idx_user_email');

    // Drop Clerk columns
    table.dropColumn('clerk_user_id');
    table.dropColumn('email');

    // Restore username to not nullable
    table.string('username').notNullable().alter();
  });
};
