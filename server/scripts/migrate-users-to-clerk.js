require("dotenv").config({ path: require("path").join(__dirname, "../.env") });
const { clerkClient } = require("@clerk/backend");
const db = require("../db");

/**
 * Script to migrate existing users from PostgreSQL to Clerk
 *
 * Prerequisites:
 * 1. Ensure all users have email addresses in the database
 * 2. Set CLERK_SECRET_KEY in .env file
 *
 * Usage:
 * node scripts/migrate-users-to-clerk.js
 *
 * Rate Limits:
 * - Clerk free tier: 5 requests per 10 seconds
 * - This script automatically handles rate limiting with delays
 */

// Color codes for console output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

// Helper function to sleep
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Helper function to log with color
function log(message, color = colors.reset) {
  console.log(`${color}${message}${colors.reset}`);
}

async function migrateUsersToClerk() {
  try {
    log("\n===========================================", colors.bright);
    log("  Clerk User Migration Script", colors.bright + colors.cyan);
    log("===========================================\n", colors.bright);

    // Step 1: Fetch all users without clerk_user_id
    log("Step 1: Fetching users from database...", colors.blue);

    const usersResult = await db.query(
      `SELECT id, username, email, first_name, last_name, created_at
       FROM users
       WHERE clerk_user_id IS NULL AND email IS NOT NULL
       ORDER BY created_at ASC`
    );

    const users = usersResult.rows;

    if (users.length === 0) {
      log("\n✅ No users to migrate. All users already have Clerk accounts.", colors.green);
      process.exit(0);
    }

    log(`   Found ${users.length} user(s) to migrate\n`, colors.cyan);

    // Step 2: Validate users have required fields
    log("Step 2: Validating user data...", colors.blue);

    const invalidUsers = users.filter((user) => !user.email || !user.first_name || !user.last_name);

    if (invalidUsers.length > 0) {
      log("\n❌ Error: Some users are missing required fields (email, first_name, last_name):", colors.red);
      invalidUsers.forEach((user) => {
        log(`   - User ID ${user.id}: ${user.username} (email: ${user.email || "MISSING"})`, colors.red);
      });
      log("\nPlease update these users manually before running migration.", colors.yellow);
      process.exit(1);
    }

    log("   All users have required fields ✓\n", colors.green);

    // Step 3: Migrate users to Clerk
    log("Step 3: Creating Clerk accounts...", colors.blue);
    log(`   Rate limit: 5 requests per 10 seconds (2.5s delay between requests)\n`, colors.yellow);

    let successCount = 0;
    let errorCount = 0;
    const errors = [];

    for (let i = 0; i < users.length; i++) {
      const user = users[i];
      const userNum = i + 1;

      log(`   [${userNum}/${users.length}] Processing: ${user.email} (${user.username})...`, colors.cyan);

      try {
        // Create user in Clerk
        const clerkUser = await clerkClient.users.createUser({
          emailAddress: [user.email],
          firstName: user.first_name,
          lastName: user.last_name,
          username: user.username,
          skipPasswordRequirement: true, // Users will set password on first login
          skipPasswordChecks: true,
        });

        const clerkUserId = clerkUser.id;

        // Update PostgreSQL database with clerk_user_id
        await db.query(
          "UPDATE users SET clerk_user_id = $1, updated_at = NOW() WHERE id = $2",
          [clerkUserId, user.id]
        );

        log(`   ✅ Created Clerk account: ${clerkUserId}`, colors.green);
        successCount++;

        // Rate limiting: Wait 2.5 seconds between requests (5 requests per 10 seconds)
        if (i < users.length - 1) {
          log(`   ⏳ Waiting 2.5s for rate limit...`, colors.yellow);
          await sleep(2500);
        }
      } catch (error) {
        log(`   ❌ Error creating Clerk account: ${error.message}`, colors.red);
        errorCount++;
        errors.push({
          user: user.email,
          error: error.message,
        });

        // If rate limit error, wait longer
        if (error.message && error.message.includes("rate limit")) {
          log(`   ⏳ Rate limit hit, waiting 15 seconds...`, colors.yellow);
          await sleep(15000);
        }
      }
    }

    // Step 4: Summary
    log("\n===========================================", colors.bright);
    log("  Migration Summary", colors.bright + colors.cyan);
    log("===========================================\n", colors.bright);

    log(`Total users processed: ${users.length}`, colors.cyan);
    log(`✅ Successfully migrated: ${successCount}`, colors.green);
    log(`❌ Failed: ${errorCount}`, colors.red);

    if (errors.length > 0) {
      log("\n⚠️  Errors:", colors.yellow);
      errors.forEach((err) => {
        log(`   - ${err.user}: ${err.error}`, colors.red);
      });
    }

    log("\n✨ Migration complete!\n", colors.green);

    // Close database connection
    await db.end();
    process.exit(errorCount > 0 ? 1 : 0);
  } catch (error) {
    log(`\n❌ Fatal error during migration: ${error.message}`, colors.red);
    console.error(error);
    await db.end();
    process.exit(1);
  }
}

// Check if Clerk secret key is configured
if (!process.env.CLERK_SECRET_KEY) {
  log("\n❌ Error: CLERK_SECRET_KEY not found in environment variables", colors.red);
  log("Please add it to your .env file:\n", colors.yellow);
  log("CLERK_SECRET_KEY=sk_test_...\n", colors.yellow);
  process.exit(1);
}

// Run migration
migrateUsersToClerk();
