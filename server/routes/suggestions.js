const express = require('express');
const router = express.Router();
const graphService = require('../services/graphService');
const { authenticateToken } = require('../middleware/authMiddleware');
const db = require('../db');

/**
 * Snapchat-style friend suggestion algorithm
 * - Prioritizes people from your country/city when location is enabled
 * - Learns from your friend network (if you add many French friends, shows more French people)
 * - Mixes in random suggestions for diversity
 * - Works even without location data
 */
router.get('/:userId', authenticateToken, async (req, res) => {
  const { userId } = req.params;

  try {
    // Try to get suggestions from RedisGraph first (for users with large networks)
    let suggestions = await graphService.getFriendSuggestions(userId);

    // Fallback: Use smart SQL-based suggestions
    if (suggestions.length === 0) {
      console.log(`Using smart SQL-based suggestions for user ${userId}`);

      // Get current user's location and their friends' countries to learn preferences
      const userDataQuery = await db.query(`
        SELECT
          u.country,
          u.country_code,
          u.city,
          u.state,
          u.location_enabled
        FROM users u
        WHERE u.id = $1
      `, [userId]);

      const currentUser = userDataQuery.rows[0];
      const hasLocation = currentUser && currentUser.location_enabled;

      // Analyze user's friend network to learn preferences
      const friendNetworkQuery = await db.query(`
        SELECT
          u.country_code,
          COUNT(*) as friend_count
        FROM friends f
        JOIN users u ON u.id = f.friend_id
        WHERE f.user_id = $1
          AND f.status = 'accepted'
          AND u.country_code IS NOT NULL
        GROUP BY u.country_code
        ORDER BY friend_count DESC
        LIMIT 5
      `, [userId]);

      const preferredCountries = friendNetworkQuery.rows.map(row => row.country_code);
      const totalFriends = friendNetworkQuery.rows.reduce((sum, row) => sum + parseInt(row.friend_count), 0);

      // Build smart suggestion query with weighted scoring
      let scoredSuggestions = [];

      // 1. Same city suggestions (highest priority if location enabled) - 40%
      if (hasLocation && currentUser.city) {
        const sameCityQuery = await db.query(`
          SELECT
            u.id AS "userId",
            CONCAT(u.first_name, ' ', u.last_name) AS name,
            u.first_name AS "firstName",
            u.last_name AS "lastName",
            u.username,
            u.country,
            u.country_code AS "countryCode",
            u.state,
            u.city,
            u.verified,
            u.developer,
            100 AS score
          FROM users u
          WHERE u.id != $1
            AND u.city = $2
            AND u.country_code = $3
            AND u.id NOT IN (
              SELECT friend_id FROM friends WHERE user_id = $1 AND status IN ('accepted', 'pending')
              UNION
              SELECT user_id FROM friends WHERE friend_id = $1 AND status IN ('accepted', 'pending')
            )
          ORDER BY RANDOM()
          LIMIT 8
        `, [userId, currentUser.city, currentUser.country_code]);

        scoredSuggestions.push(...sameCityQuery.rows);
      }

      // 2. Same country suggestions - 30%
      if (hasLocation && currentUser.country_code) {
        const sameCountryQuery = await db.query(`
          SELECT
            u.id AS "userId",
            CONCAT(u.first_name, ' ', u.last_name) AS name,
            u.first_name AS "firstName",
            u.last_name AS "lastName",
            u.username,
            u.country,
            u.country_code AS "countryCode",
            u.state,
            u.city,
            u.verified,
            u.developer,
            70 AS score
          FROM users u
          WHERE u.id != $1
            AND u.country_code = $2
            AND (u.city != $3 OR u.city IS NULL)
            AND u.id NOT IN (
              SELECT friend_id FROM friends WHERE user_id = $1 AND status IN ('accepted', 'pending')
              UNION
              SELECT user_id FROM friends WHERE friend_id = $1 AND status IN ('accepted', 'pending')
            )
          ORDER BY RANDOM()
          LIMIT 6
        `, [userId, currentUser.country_code, currentUser.city || '']);

        scoredSuggestions.push(...sameCountryQuery.rows);
      }

      // 3. Countries from your friend network (learning from your behavior) - 20%
      if (preferredCountries.length > 0) {
        const networkCountriesQuery = await db.query(`
          SELECT
            u.id AS "userId",
            CONCAT(u.first_name, ' ', u.last_name) AS name,
            u.first_name AS "firstName",
            u.last_name AS "lastName",
            u.username,
            u.country,
            u.country_code AS "countryCode",
            u.state,
            u.city,
            u.verified,
            u.developer,
            CASE
              WHEN u.country_code = ANY($2::text[]) THEN 50
              ELSE 30
            END AS score
          FROM users u
          WHERE u.id != $1
            AND u.country_code = ANY($2::text[])
            AND (NOT $3::boolean OR u.country_code != $4)
            AND u.id NOT IN (
              SELECT friend_id FROM friends WHERE user_id = $1 AND status IN ('accepted', 'pending')
              UNION
              SELECT user_id FROM friends WHERE friend_id = $1 AND status IN ('accepted', 'pending')
            )
          ORDER BY RANDOM()
          LIMIT 4
        `, [userId, preferredCountries, hasLocation, currentUser.country_code || '']);

        scoredSuggestions.push(...networkCountriesQuery.rows);
      }

      // 4. Random global suggestions for diversity - 10%
      const randomQuery = await db.query(`
        SELECT
          u.id AS "userId",
          CONCAT(u.first_name, ' ', u.last_name) AS name,
          u.first_name AS "firstName",
          u.last_name AS "lastName",
          u.username,
          u.country,
          u.country_code AS "countryCode",
          u.state,
          u.city,
          u.verified,
          u.developer,
          10 AS score
        FROM users u
        WHERE u.id != $1
          AND u.id NOT IN (
            SELECT friend_id FROM friends WHERE user_id = $1 AND status IN ('accepted', 'pending')
            UNION
            SELECT user_id FROM friends WHERE friend_id = $1 AND status IN ('accepted', 'pending')
          )
        ORDER BY RANDOM()
        LIMIT 2
      `, [userId]);

      scoredSuggestions.push(...randomQuery.rows);

      // Remove duplicates (keep highest score)
      const uniqueSuggestions = new Map();
      scoredSuggestions.forEach(suggestion => {
        const existing = uniqueSuggestions.get(suggestion.userId);
        if (!existing || suggestion.score > existing.score) {
          uniqueSuggestions.set(suggestion.userId, suggestion);
        }
      });

      // Convert to array and sort by score
      suggestions = Array.from(uniqueSuggestions.values())
        .sort((a, b) => b.score - a.score)
        .slice(0, 20);

      console.log(`Generated ${suggestions.length} smart suggestions for user ${userId}`);
    }

    res.json(suggestions);
  } catch (error) {
    console.error('Error fetching friend suggestions:', error);
    res.status(500).json({ message: 'Error fetching friend suggestions.' });
  }
});

/**
 * Search for users by name or username
 * Returns ALL users matching the query (not filtered by friend status)
 */
router.get('/search/:userId', authenticateToken, async (req, res) => {
  const { userId } = req.params;
  const { query } = req.query;

  try {
    if (!query || query.trim().length === 0) {
      return res.json([]);
    }

    const searchTerm = `%${query.toLowerCase()}%`;

    // Search for users by name or username
    const result = await db.query(`
      SELECT
        u.id AS "userId",
        CONCAT(u.first_name, ' ', u.last_name) AS name,
        u.first_name AS "firstName",
        u.last_name AS "lastName",
        u.username,
        u.country,
        u.country_code AS "countryCode",
        u.state,
        u.city,
        u.verified,
        u.developer,
        CASE
          WHEN f1.status = 'accepted' OR f2.status = 'accepted' THEN 'friend'
          WHEN f1.status = 'pending' OR f2.status = 'pending' THEN 'pending'
          ELSE 'none'
        END AS "friendStatus"
      FROM users u
      LEFT JOIN friends f1 ON f1.user_id = $1 AND f1.friend_id = u.id
      LEFT JOIN friends f2 ON f2.user_id = u.id AND f2.friend_id = $1
      WHERE u.id != $1
        AND (
          LOWER(CONCAT(u.first_name, ' ', u.last_name)) LIKE $2
          OR LOWER(u.username) LIKE $2
        )
      ORDER BY
        CASE WHEN LOWER(u.username) = LOWER($3) THEN 1 ELSE 2 END,
        CASE WHEN LOWER(u.username) LIKE $2 THEN 1 ELSE 2 END,
        u.username
      LIMIT 50
    `, [userId, searchTerm, query.toLowerCase()]);

    res.json(result.rows);
  } catch (error) {
    console.error('Error searching users:', error);
    res.status(500).json({ message: 'Error searching users.' });
  }
});

module.exports = router;
