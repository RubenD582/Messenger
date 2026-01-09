/**
 * Migration: Create Daily Remix tables
 *
 * Tables:
 * - remix_groups: Friend groups for daily remixes
 * - remix_posts: Base photos posted each day
 * - remix_layers: Additions/layers added by friends
 */

exports.up = async function(knex) {
  // Create remix_groups table
  await knex.schema.createTable('remix_groups', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.string('name', 100); // Optional group name
    table.uuid('created_by').notNullable();
    table.timestamp('created_at').defaultTo(knex.fn.now());
    table.timestamp('updated_at').defaultTo(knex.fn.now());
    table.boolean('is_active').defaultTo(true);

    // Indexes
    table.index('created_by');
    table.index('is_active');
  });

  // Create remix_group_members table (many-to-many)
  await knex.schema.createTable('remix_group_members', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.uuid('group_id').notNullable();
    table.uuid('user_id').notNullable();
    table.timestamp('joined_at').defaultTo(knex.fn.now());
    table.integer('streak_count').defaultTo(0); // Days participated in a row

    // Foreign keys
    table.foreign('group_id').references('id').inTable('remix_groups').onDelete('CASCADE');
    table.foreign('user_id').references('id').inTable('users').onDelete('CASCADE');

    // Unique constraint: user can only be in a group once
    table.unique(['group_id', 'user_id']);

    // Indexes
    table.index('user_id');
    table.index('group_id');
  });

  // Create remix_posts table (base photos)
  await knex.schema.createTable('remix_posts', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.uuid('group_id').notNullable();
    table.uuid('posted_by').notNullable();
    table.date('post_date').notNullable(); // Which day this post is for
    table.string('image_url', 500).notNullable(); // Full-size image URL
    table.string('thumbnail_url', 500).notNullable(); // Thumbnail URL
    table.integer('image_width');
    table.integer('image_height');
    table.string('theme', 100); // Optional: "chaos", "morning", "vibe check", etc.
    table.timestamp('created_at').defaultTo(knex.fn.now());
    table.timestamp('expires_at'); // When remix window closes (e.g., 12 hours later)
    table.boolean('is_complete').defaultTo(false); // Marked complete when window closes

    // Foreign keys
    table.foreign('group_id').references('id').inTable('remix_groups').onDelete('CASCADE');
    table.foreign('posted_by').references('id').inTable('users').onDelete('CASCADE');

    // Unique constraint: one base post per group per day
    table.unique(['group_id', 'post_date']);

    // Indexes
    table.index('group_id');
    table.index('posted_by');
    table.index('post_date');
    table.index('expires_at');
    table.index(['group_id', 'post_date']);
  });

  // Create remix_layers table (additions to base photos)
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

  // Create remix_reactions table (optional: reactions to completed remixes)
  await knex.schema.createTable('remix_reactions', (table) => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.uuid('post_id').notNullable();
    table.uuid('user_id').notNullable();
    table.string('reaction_type', 20).notNullable(); // 'fire', 'laugh', 'love', etc.
    table.timestamp('created_at').defaultTo(knex.fn.now());

    // Foreign keys
    table.foreign('post_id').references('id').inTable('remix_posts').onDelete('CASCADE');
    table.foreign('user_id').references('id').inTable('users').onDelete('CASCADE');

    // Unique constraint: one reaction per user per post
    table.unique(['post_id', 'user_id']);

    // Indexes
    table.index('post_id');
  });

  console.log('✅ Created Daily Remix tables');
};

exports.down = async function(knex) {
  // Drop tables in reverse order (respect foreign keys)
  await knex.schema.dropTableIfExists('remix_reactions');
  await knex.schema.dropTableIfExists('remix_layers');
  await knex.schema.dropTableIfExists('remix_posts');
  await knex.schema.dropTableIfExists('remix_group_members');
  await knex.schema.dropTableIfExists('remix_groups');

  console.log('✅ Dropped Daily Remix tables');
};
