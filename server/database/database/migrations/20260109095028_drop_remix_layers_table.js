/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = async function(knex) {
  await knex.schema.dropTableIfExists('remix_layers');
  console.log('✅ Dropped remix_layers table');
};

exports.down = async function(knex) {
  await knex.schema.createTable('remix_layers', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.uuid('post_id').notNullable();
    table.uuid('added_by').notNullable();
    table.enum('layer_type', ['photo', 'sticker', 'text', 'drawing']).notNullable();

    // Content based on layer type
    table.string('content_url', 500); // For photos/stickers
    table.text('text_content'); // For text layers
    table.jsonb('drawing_data'); // For drawings (stroke paths, colors, etc.)
    table.jsonb('sticker_data'); // For stickers (sticker_id, etc.)

    // Positioning (relative to base image, 0-1 normalized)
    table.decimal('position_x', 5, 4).notNullable().defaultTo(0.5); // 0.0 to 1.0
    table.decimal('position_y', 5, 4).notNullable().defaultTo(0.5); // 0.0 to 1.0
    table.decimal('scale', 4, 3).notNullable().defaultTo(1.0); // 0.1 to 10.0
    table.decimal('rotation', 5, 2).notNullable().defaultTo(0); // -180 to 180 degrees
    table.integer('z_index').defaultTo(0); // Layer order

    // Metadata
    table.jsonb('metadata'); // Additional props (colors, effects, etc.)
    table.timestamp('created_at').defaultTo(knex.fn.now());

    // Foreign keys
    table.foreign('post_id').references('id').inTable('remix_posts').onDelete('CASCADE');
    table.foreign('added_by').references('id').inTable('users').onDelete('CASCADE');

    // Indexes
    table.index('post_id');
    table.index('added_by');
    table.index(['post_id', 'created_at']); // For chronological ordering
  });
  console.log('✅ Recreated remix_layers table');
};
