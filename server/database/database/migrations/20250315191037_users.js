/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
	return knex.schema.createTable('users', function(table) {
	  table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
	  table.string('first_name').notNullable();
	  table.string('last_name').notNullable();
	  table.string('username').notNullable().unique();
	  table.string('password').notNullable();
	  table.timestamps(true, true);
	});
  };
  
  /**
   * @param { import("knex").Knex } knex
   * @returns { Promise<void> }
   */
  exports.down = function(knex) {
	return knex.schema.dropTableIfExists('users');
  };
  