/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = async function(knex) {
  return knex.schema.createTable('statuses', function(table) {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.uuid('user_id').notNullable().references('id').inTable('users').onDelete('CASCADE');
    table.text('text_content').notNullable();
    table.string('background_color', 7).notNullable(); // Hex color code (#RRGGBB)
    table.timestamp('created_at').defaultTo(knex.fn.now());

    // Indexes for efficient querying
    table.index(['user_id', 'created_at'], 'idx_user_created');
    table.index('created_at', 'idx_created_expiry');
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.dropTableIfExists('statuses');
};
