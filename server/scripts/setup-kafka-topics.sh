#!/bin/bash

# Kafka Topics Setup Script for Real-Time Chat System
# This script creates the necessary Kafka topics for handling chat messages,
# typing indicators, and read receipts

echo "Creating Kafka topics for chat system..."

# Chat messages topic (high throughput, 10 partitions for scalability)
docker-compose exec kafka kafka-topics --create \
  --topic chat-messages \
  --partitions 10 \
  --replication-factor 1 \
  --bootstrap-server kafka:9092 \
  --if-not-exists

echo "✓ Created chat-messages topic"

# Typing indicators topic (ephemeral events, 5 partitions)
docker-compose exec kafka kafka-topics --create \
  --topic typing-indicators \
  --partitions 5 \
  --replication-factor 1 \
  --bootstrap-server kafka:9092 \
  --if-not-exists

echo "✓ Created typing-indicators topic"

# Read receipts topic (acknowledgments, 5 partitions)
docker-compose exec kafka kafka-topics --create \
  --topic read-receipts \
  --partitions 5 \
  --replication-factor 1 \
  --bootstrap-server kafka:9092 \
  --if-not-exists

echo "✓ Created read-receipts topic"

# List all topics to verify
echo ""
echo "Verifying topics..."
docker-compose exec kafka kafka-topics --list --bootstrap-server kafka:9092

echo ""
echo "✅ Kafka topics setup complete!"
