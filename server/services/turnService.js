// turnService.js - Service for managing turn-based remix logic
const db = require('../db');

class TurnService {
  /**
   * Initialize turn order for a new post
   * Randomly selects a member to start, then sets order
   */
  async initializeTurnOrder(postId, groupId) {
    try {
      // Get all group members
      const membersResult = await db.query(`
        SELECT user_id
        FROM remix_group_members
        WHERE group_id = $1
        ORDER BY RANDOM()
      `, [groupId]);

      const members = membersResult.rows.map(row => row.user_id);

      if (members.length === 0) {
        throw new Error('No members found for group');
      }

      // Randomly select starting player
      const currentTurnUserId = members[0];

      // Update post with turn information
      await db.query(`
        UPDATE remix_posts
        SET current_turn_user_id = $1,
            turn_order = $2,
            contributors = $3,
            turn_count = 0,
            max_turns = $4
        WHERE id = $5
      `, [
        currentTurnUserId,
        JSON.stringify(members),
        JSON.stringify([]), // No contributors yet (base post doesn't count as a turn)
        members.length,
        postId
      ]);

      console.log(`✅ Initialized turn order for post ${postId}. Starting user: ${currentTurnUserId}`);

      return {
        currentTurnUserId,
        turnOrder: members,
        turnCount: 0,
        maxTurns: members.length
      };
    } catch (error) {
      console.error('Error initializing turn order:', error);
      throw error;
    }
  }

  /**
   * Check if it's a specific user's turn
   */
  async isUserTurn(postId, userId) {
    try {
      const result = await db.query(`
        SELECT current_turn_user_id, contributors
        FROM remix_posts
        WHERE id = $1
      `, [postId]);

      if (result.rows.length === 0) {
        return { isMyTurn: false, reason: 'Post not found' };
      }

      const post = result.rows[0];

      // If turn order not initialized yet, return true (allow base post creation)
      if (!post.current_turn_user_id) {
        return { isMyTurn: true, reason: 'Turn order not initialized' };
      }

      // Safely parse contributors, handling NULL, empty string, or invalid JSON
      let contributors = [];
      try {
        if (post.contributors) {
          contributors = typeof post.contributors === 'string'
            ? JSON.parse(post.contributors)
            : post.contributors;
        }
      } catch (e) {
        console.warn(`Failed to parse contributors for post ${postId}:`, e);
        contributors = [];
      }

      // Check if user already contributed this round
      if (contributors.includes(userId)) {
        return { isMyTurn: false, reason: 'Already contributed this round' };
      }

      // Check if it's their turn
      const isMyTurn = post.current_turn_user_id === userId;

      return {
        isMyTurn,
        reason: isMyTurn ? 'Your turn' : 'Not your turn',
        currentTurnUserId: post.current_turn_user_id
      };
    } catch (error) {
      console.error('Error checking user turn:', error);
      throw error;
    }
  }

  /**
   * Advance to next user's turn after a contribution
   */
  async advanceTurn(postId, userId) {
    try {
      // Get current post state
      const postResult = await db.query(`
        SELECT current_turn_user_id, turn_order, contributors, turn_count, max_turns, is_complete
        FROM remix_posts
        WHERE id = $1
      `, [postId]);

      if (postResult.rows.length === 0) {
        throw new Error('Post not found');
      }

      const post = postResult.rows[0];

      // Safely parse turn_order
      let turnOrder = [];
      try {
        if (post.turn_order) {
          turnOrder = typeof post.turn_order === 'string'
            ? JSON.parse(post.turn_order)
            : post.turn_order;
        }
      } catch (e) {
        console.warn(`Failed to parse turn_order for post ${postId}:`, e);
        turnOrder = [];
      }

      // Safely parse contributors
      let contributors = [];
      try {
        if (post.contributors) {
          contributors = typeof post.contributors === 'string'
            ? JSON.parse(post.contributors)
            : post.contributors;
        }
      } catch (e) {
        console.warn(`Failed to parse contributors for post ${postId}:`, e);
        contributors = [];
      }

      // Add current user to contributors if not already there
      if (!contributors.includes(userId)) {
        contributors.push(userId);
      }

      const newTurnCount = post.turn_count + 1;

      // Check if all members have contributed (round complete)
      const isRoundComplete = contributors.length === turnOrder.length;

      if (isRoundComplete) {
        // Mark post as complete
        await db.query(`
          UPDATE remix_posts
          SET is_complete = true,
              turn_count = $1,
              contributors = $2,
              current_turn_user_id = NULL,
              updated_at = NOW()
          WHERE id = $3
        `, [newTurnCount, JSON.stringify(contributors), postId]);

        console.log(`✅ Post ${postId} completed! All members contributed.`);

        return {
          isComplete: true,
          currentTurnUserId: null,
          turnCount: newTurnCount,
          contributors
        };
      }

      // Find next user who hasn't contributed yet
      let nextUserIndex = turnOrder.indexOf(userId) + 1;
      let nextUser = null;

      // Loop through turn order to find next available user
      for (let i = 0; i < turnOrder.length; i++) {
        const candidateIndex = (nextUserIndex + i) % turnOrder.length;
        const candidate = turnOrder[candidateIndex];

        if (!contributors.includes(candidate)) {
          nextUser = candidate;
          break;
        }
      }

      if (!nextUser) {
        // This shouldn't happen, but fallback to marking complete
        await db.query(`
          UPDATE remix_posts
          SET is_complete = true,
              turn_count = $1,
              contributors = $2,
              current_turn_user_id = NULL,
              updated_at = NOW()
          WHERE id = $3
        `, [newTurnCount, JSON.stringify(contributors), postId]);

        return {
          isComplete: true,
          currentTurnUserId: null,
          turnCount: newTurnCount,
          contributors
        };
      }

      // Update post with next turn
      await db.query(`
        UPDATE remix_posts
        SET current_turn_user_id = $1,
            turn_count = $2,
            contributors = $3,
            updated_at = NOW()
        WHERE id = $4
      `, [nextUser, newTurnCount, JSON.stringify(contributors), postId]);

      console.log(`✅ Advanced turn for post ${postId}. Next user: ${nextUser}`);

      return {
        isComplete: false,
        currentTurnUserId: nextUser,
        turnCount: newTurnCount,
        contributors
      };
    } catch (error) {
      console.error('Error advancing turn:', error);
      throw error;
    }
  }

  /**
   * Get current turn status for a post
   */
  async getTurnStatus(postId) {
    try {
      const result = await db.query(`
        SELECT
          rp.current_turn_user_id,
          rp.turn_order,
          rp.contributors,
          rp.turn_count,
          rp.max_turns,
          rp.is_complete,
          u.first_name,
          u.last_name,
          u.username
        FROM remix_posts rp
        LEFT JOIN users u ON rp.current_turn_user_id = u.id
        WHERE rp.id = $1
      `, [postId]);

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];

      // Safely parse turn_order
      let turnOrder = [];
      try {
        if (row.turn_order) {
          turnOrder = typeof row.turn_order === 'string'
            ? JSON.parse(row.turn_order)
            : row.turn_order;
        }
      } catch (e) {
        console.warn(`Failed to parse turn_order for post ${postId}:`, e);
        turnOrder = [];
      }

      // Safely parse contributors
      let contributors = [];
      try {
        if (row.contributors) {
          contributors = typeof row.contributors === 'string'
            ? JSON.parse(row.contributors)
            : row.contributors;
        }
      } catch (e) {
        console.warn(`Failed to parse contributors for post ${postId}:`, e);
        contributors = [];
      }

      return {
        currentTurnUserId: row.current_turn_user_id,
        currentTurnUserName: row.first_name && row.last_name
          ? `${row.first_name} ${row.last_name}`
          : row.username,
        turnOrder,
        contributors,
        turnCount: row.turn_count,
        maxTurns: row.max_turns,
        isComplete: row.is_complete
      };
    } catch (error) {
      console.error('Error getting turn status:', error);
      throw error;
    }
  }
}

module.exports = new TurnService();
