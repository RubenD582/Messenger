// server/services/graphService.js
const { createClient } = require('redis');
const config = require('../config/redisClient'); // Assuming this config has Redis connection details

let graph; // RedisGraph client instance

async function connectToGraph() {
    // Ensure the Redis client from ioredis (if used elsewhere) or redis-om
    // is configured with the RedisGraph module enabled if it's not a direct RedisGraph client
    // For redis-om, the client is usually managed internally.
    // For direct RedisGraph, we might use node-redis-graph or redis-graph.
    // Given the project uses 'redis' (node-redis v4) and 'ioredis', let's use node-redis v4 for RedisGraph too.

    const client = createClient({
        url: config.redisUrl // Assuming redisUrl is available in config
    });

    client.on('error', (err) => console.error('Redis Client Error', err));
    await client.connect();

    // Check if RedisGraph module is loaded
    try {
        await client.graph.query('social_graph', 'RETURN 1');
        console.log('RedisGraph module is connected and responsive.');
    } catch (e) {
        if (e.message.includes('ERR unknown command `GRAPH.QUERY`')) {
            console.error('RedisGraph module not loaded. Please ensure RedisGraph is installed and enabled on your Redis server.');
            // Exit or throw a more specific error if RedisGraph is mandatory
            throw new Error('RedisGraph module is not loaded on the Redis server.');
        }
        console.error('Error connecting to RedisGraph:', e.message);
        throw e;
    }

    // Initialize the RedisGraph client with the graph name
    // For node-redis v4, graph commands are available directly via client.graph
    graph = client.graph; // Assign the graph client
    console.log('Connected to RedisGraph and initialized graph: social_graph');
}

// Function to ensure a user node exists (idempotent)
async function ensureUserNode(userId, name, country, province, city) {
    if (!graph) await connectToGraph();

    const query = `
        MERGE (u:User {userId: $userId})
        ON CREATE SET u.name = $name, u.country = $country, u.province = $province, u.city = $city, u.createdAt = datetime()
        ON MATCH SET u.name = $name, u.country = $country, u.province = $province, u.city = $city, u.updatedAt = datetime()
        RETURN u
    `;
    const params = { userId, name, country, province, city };
    await graph.query('social_graph', query, params);
}

// Function to ensure a friendship relationship exists (bidirectional)
async function ensureFriendship(userAId, userBId) {
    if (!graph) await connectToGraph();

    const query = `
        MATCH (a:User {userId: $userAId})
        MATCH (b:User {userId: $userBId})
        MERGE (a)-[:FRIENDS_WITH]->(b)
        MERGE (b)-[:FRIENDS_WITH]->(a)
    `;
    const params = { userAId, userBId };
    await graph.query('social_graph', query, params);
}

// Function to get friend suggestions
async function getFriendSuggestions(currentUserId, limit = 10) {
    if (!graph) await connectToGraph();

    // Get current user's geographical data and existing friends
    const currentUserDataQuery = `
        MATCH (me:User {userId: $currentUserId})
        OPTIONAL MATCH (me)-[:FRIENDS_WITH]->(friend:User)
        RETURN me.country AS myCountry, me.province AS myProvince, COLLECT(friend.userId) AS myFriends
    `;
    const currentUserResult = await graph.query('social_graph', currentUserDataQuery, { currentUserId });

    if (currentUserResult.data.length === 0) {
        console.warn(`User ${currentUserId} not found in graph.`);
        return [];
    }

    const myCountry = currentUserResult.data[0][0];
    const myProvince = currentUserResult.data[0][1];
    const myFriends = new Set(currentUserResult.data[0][2]);
    myFriends.add(currentUserId); // Exclude self from suggestions

    let suggestionsMap = new Map(); // Map to store userId -> score

    // 1. Mutual Friends (Weight: 5.0 per mutual friend)
    const mutualFriendsQuery = `
        MATCH (me:User {userId: $currentUserId})-[:FRIENDS_WITH]->(myFriend:User)
        MATCH (myFriend)-[:FRIENDS_WITH]->(suggestedFriend:User)
        WHERE NOT (suggestedFriend.userId IN $myFriends)
          AND me.userId <> suggestedFriend.userId
        RETURN suggestedFriend.userId AS userId, COUNT(DISTINCT myFriend) AS mutualFriendsCount
        ORDER BY mutualFriendsCount DESC
        LIMIT ${limit} // Limit here for efficiency, combined later
    `;
    const mutualFriendsResult = await graph.query('social_graph', mutualFriendsQuery, { currentUserId, myFriends: Array.from(myFriends) });
    mutualFriendsResult.data.forEach(row => {
        const userId = row[0];
        const score = row[1] * 5.0; // Higher weight for mutual friends
        suggestionsMap.set(userId, (suggestionsMap.get(userId) || 0) + score);
    });


    // 2. Same Province (Weight: 3.0) - only if current user has a province
    if (myProvince) {
        const sameProvinceQuery = `
            MATCH (suggestedFriend:User)
            WHERE suggestedFriend.country = $myCountry
              AND suggestedFriend.province = $myProvince
              AND NOT (suggestedFriend.userId IN $myFriends)
              AND suggestedFriend.userId <> $currentUserId
            RETURN suggestedFriend.userId AS userId, 1 AS score
            LIMIT ${limit}
        `;
        const sameProvinceResult = await graph.query('social_graph', sameProvinceQuery, { myCountry, myProvince, myFriends: Array.from(myFriends), currentUserId });
        sameProvinceResult.data.forEach(row => {
            const userId = row[0];
            const score = row[1] * 3.0;
            suggestionsMap.set(userId, (suggestionsMap.get(userId) || 0) + score);
        });
    }


    // 3. Same Country (Weight: 1.0) - only if current user has a country
    if (myCountry) {
        const sameCountryQuery = `
            MATCH (suggestedFriend:User)
            WHERE suggestedFriend.country = $myCountry
              AND suggestedFriend.province <> $myProvince // Exclude those already covered by same province
              AND NOT (suggestedFriend.userId IN $myFriends)
              AND suggestedFriend.userId <> $currentUserId
            RETURN suggestedFriend.userId AS userId, 1 AS score
            LIMIT ${limit}
        `;
        const sameCountryResult = await graph.query('social_graph', sameCountryQuery, { myCountry, myProvince, myFriends: Array.from(myFriends), currentUserId });
        sameCountryResult.data.forEach(row => {
            const userId = row[0];
            const score = row[1] * 1.0;
            suggestionsMap.set(userId, (suggestionsMap.get(userId) || 0) + score);
        });
    }

    // 4. Random Discovery (Weight: 0.1)
    const randomQuery = `
        MATCH (suggestedFriend:User)
        WHERE NOT (suggestedFriend.userId IN $myFriends)
          AND suggestedFriend.userId <> $currentUserId
        RETURN suggestedFriend.userId AS userId, rand() AS score // Use rand() for randomized scoring
        ORDER BY score DESC // To get a somewhat random set with limit
        LIMIT ${Math.floor(limit / 2)} // Get fewer random suggestions
    `;
    const randomResult = await graph.query('social_graph', randomQuery, { myFriends: Array.from(myFriends), currentUserId });
    randomResult.data.forEach(row => {
        const userId = row[0];
        // Scale random score to be low, but enough to get some variety
        const score = (row[1] * 0.1);
        suggestionsMap.set(userId, (suggestionsMap.get(userId) || 0) + score);
    });


    // Convert map to sorted array of suggestions
    const sortedSuggestions = Array.from(suggestionsMap.entries())
        .sort((a, b) => b[1] - a[1]) // Sort by score descending
        .slice(0, limit) // Take top 'limit' suggestions after scoring
        .map(entry => ({ userId: entry[0], score: entry[1] })); // Format as objects

    const userIdsToFetch = sortedSuggestions.map(s => s.userId);

    if (userIdsToFetch.length === 0) {
        return [];
    }

    // Fetch details for the suggested user IDs
    const userDetailsQuery = `
        MATCH (u:User)
        WHERE u.userId IN $userIds
        RETURN u.userId, u.name, u.country, u.province, u.city
    `;
    const userDetailsResult = await graph.query('social_graph', userDetailsQuery, { userIds: userIdsToFetch });

    // Create a map for easy lookup
    const userDetailsMap = new Map();
    userDetailsResult.data.forEach(row => {
        userDetailsMap.set(row[0], {
            userId: row[0],
            name: row[1],
            country: row[2],
            province: row[3],
            city: row[4]
            // NOTE: profile_picture is not in the graph node currently
        });
    });

    // Combine scores with details
    const finalSuggestions = sortedSuggestions.map(s => {
        const details = userDetailsMap.get(s.userId);
        return {
            ...details,
            score: s.score
        };
    }).filter(s => s.userId); // Filter out any potential nulls if details weren't found

    return finalSuggestions;
}

module.exports = {
    connectToGraph,
    ensureUserNode,
    ensureFriendship,
    getFriendSuggestions,
};