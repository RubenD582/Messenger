/**
 * Migration to remove Clerk integration and set up custom OTP-based authentication
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = async function(knex) {
  // Step 1: Update existing users with NULL emails to have a temporary email
  // This allows the migration to proceed without data loss
  await knex.raw(`
    UPDATE users
    SET email = CONCAT('user_', id, '@temp.messenger.local')
    WHERE email IS NULL
  `);

  // Step 2: Drop Clerk indexes and constraints if they exist (using raw SQL to handle gracefully)
  await knex.raw('DROP INDEX IF EXISTS idx_clerk_user_id');
  await knex.raw('DROP INDEX IF EXISTS idx_user_email');
  await knex.raw('ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_unique');

  // Step 3: Drop Clerk column if it exists
  const hasClerkColumn = await knex.schema.hasColumn('users', 'clerk_user_id');
  if (hasClerkColumn) {
    await knex.schema.table('users', function(table) {
      table.dropColumn('clerk_user_id');
    });
  }

  // Step 4: Update schema
  return knex.schema.table('users', function(table) {
    // Make email required and unique (was nullable for Clerk)
    table.string('email').notNullable().unique().alter();

    // Make username nullable (users can sign up with email only)
    // Username can be set later in profile
    table.string('username').nullable().alter();

    // Add email_verified column (replacing generic 'verified')
    table.boolean('email_verified').notNullable().defaultTo(false);

    // Add last_login timestamp
    table.timestamp('last_login').nullable();

    // Add indexes for performance
    table.index('email', 'idx_users_email');
    table.index('email_verified', 'idx_users_email_verified');
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.table('users', function(table) {
    // Restore Clerk integration
    table.string('clerk_user_id').nullable().unique();
    table.index('clerk_user_id', 'idx_clerk_user_id');

    // Revert email to nullable
    table.string('email').nullable().alter();
    table.index('email', 'idx_user_email');

    // Remove custom auth columns
    table.dropIndex('email', 'idx_users_email');
    table.dropIndex('email_verified', 'idx_users_email_verified');
    table.dropColumn('email_verified');
    table.dropColumn('last_login');

    // Restore username to not nullable
    table.string('username').notNullable().alter();
  });
};
