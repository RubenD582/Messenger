require("dotenv").config();
const { Client } = require("pg");

const db = new Client({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT
});

db.connect((err) => {
  if (err) {
    console.error("PostgreSQL Connection Error:", err);
    return;
  }
  console.log("PostgreSQL Connected...");
});

module.exports = db;
