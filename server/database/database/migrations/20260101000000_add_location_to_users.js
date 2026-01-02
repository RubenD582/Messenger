/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = async function(knex) {
  await knex.schema.table('users', function(table) {
    // Location fields for friend suggestions
    table.string('country', 100);
    table.string('country_code', 2); // ISO 2-letter country code (e.g., 'ZA', 'FR')
    table.string('city', 100);
    table.string('state', 100); // State/Province
    table.decimal('latitude', 10, 7); // For precise location matching
    table.decimal('longitude', 10, 7);

    // Tracking fields
    table.timestamp('location_updated_at');
    table.boolean('location_enabled').defaultTo(false);

    // Add indexes for better query performance
    table.index('country_code');
    table.index('city');
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.table('users', function(table) {
    table.dropColumn('country');
    table.dropColumn('country_code');
    table.dropColumn('city');
    table.dropColumn('state');
    table.dropColumn('latitude');
    table.dropColumn('longitude');
    table.dropColumn('location_updated_at');
    table.dropColumn('location_enabled');
  });
};
