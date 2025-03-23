require("dotenv").config();

/**
 * @type { Object.<string, import("knex").Knex.Config> }
 */
module.exports = {
  development: {
    client: "pg",
    connection: {
      host: process.env.DB_HOST || "127.0.0.1",
      user: process.env.DB_USER || "postgres",
      password: process.env.DB_PASSWORD || "",
      database: process.env.DB_NAME || "messenger",
      port: process.env.DB_PORT || 5432,
    },
    pool: { min: 2, max: 10 },
    migrations: { directory: "./database/migrations" },
    seeds: { directory: "./database/seeds" },
  },

  staging: {
    client: "pg",
    connection: {
      host: process.env.STAGING_DB_HOST || "staging-db-host",
      user: process.env.STAGING_DB_USER || "staging-user",
      password: process.env.STAGING_DB_PASSWORD || "",
      database: process.env.STAGING_DB_NAME || "staging-database",
      port: process.env.STAGING_DB_PORT || 5432,
    },
    pool: { min: 2, max: 10 },
    migrations: { tableName: "knex_migrations", directory: "./database/migrations" },
    seeds: { directory: "./database/seeds" },
  },

  production: {
    client: "pg",
    connection: process.env.DATABASE_URL || {
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      ssl: { rejectUnauthorized: true }, // Enable SSL for production
    },
    pool: { min: 2, max: 20 },
    migrations: { tableName: "knex_migrations", directory: "./database/migrations" },
    seeds: { directory: "./database/seeds" },
  },
};
