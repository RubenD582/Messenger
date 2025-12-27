#!/bin/bash

echo "🚀 Starting Redis Sentinel High Availability Setup"
echo "=================================================="
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

# Stop existing Redis if running
echo "📦 Stopping old Redis containers..."
docker stop redis 2>/dev/null || true
docker rm redis 2>/dev/null || true

# Start Redis Master and Replica
echo "🔴 Starting Redis Master..."
docker-compose up -d redis-master

echo "🔵 Starting Redis Replica..."
docker-compose up -d redis-replica

# Wait for Redis instances to be ready
echo "⏳ Waiting for Redis instances to initialize..."
sleep 5

# Start Sentinel instances
echo "👁️  Starting Redis Sentinel nodes..."
docker-compose up -d redis-sentinel-1 redis-sentinel-2 redis-sentinel-3

# Wait for Sentinels to initialize
echo "⏳ Waiting for Sentinels to form quorum..."
sleep 10

# Check status
echo ""
echo "✅ Checking Redis Sentinel Status..."
echo "-----------------------------------"

# Check if master is running
if docker exec redis-master redis-cli -a redispass123 ping 2>/dev/null | grep -q PONG; then
    echo "✅ Redis Master: Running"
else
    echo "❌ Redis Master: Not responding"
fi

# Check if replica is running
if docker exec redis-replica redis-cli -a redispass123 ping 2>/dev/null | grep -q PONG; then
    echo "✅ Redis Replica: Running"
else
    echo "❌ Redis Replica: Not responding"
fi

# Check Sentinel
echo ""
echo "👁️  Sentinel Status:"
docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL master mymaster 2>/dev/null | grep -E "(ip|port|flags)" | head -3

echo ""
echo "=================================================="
echo "✅ Redis Sentinel setup complete!"
echo ""
echo "Next steps:"
echo "1. Start remaining services: docker-compose up -d"
echo "2. Check server logs: docker logs -f <server-container>"
echo "3. Test failover: docker stop redis-master"
echo ""
echo "📖 See REDIS_SENTINEL_SETUP.md for full documentation"
