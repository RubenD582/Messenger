/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.raw(`
    -- Convert absolute URLs to relative paths in remix_posts
    UPDATE remix_posts
    SET
      image_url = REGEXP_REPLACE(image_url, '^https?://[^/]+', '', 'g'),
      thumbnail_url = REGEXP_REPLACE(thumbnail_url, '^https?://[^/]+', '', 'g')
    WHERE
      image_url LIKE 'http%' OR thumbnail_url LIKE 'http%';
  `);
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  // No-op: Cannot reliably reverse this migration without knowing the original base URL
  // The application will handle prepending the current base URL at runtime
  return Promise.resolve();
};
