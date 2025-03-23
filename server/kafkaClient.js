// kafkaClient.js
const { Kafka } = require('kafkajs');

const kafka = new Kafka({
    brokers: [process.env.KAFKA_BROKER || 'localhost:9092'],
    clientId: 'messenger-app',
});
  

// Create shared producer instance
const producer = kafka.producer();

// Create shared consumer instance
const consumer = kafka.consumer({ groupId: 'friend-events-group' });

async function connectKafkaConsumer() {
    const retries = 5;
    let attempt = 0;
    while (attempt < retries) {
        try {
            await consumer.connect();
            console.log('Kafka consumer connected');
            return;
        } catch (error) {
            console.error(`Error connecting to Kafka (attempt ${attempt + 1}/${retries}):`, error);
            attempt++;
            if (attempt < retries) {
                console.log('Retrying...');
                await new Promise(resolve => setTimeout(resolve, 5000)); // Retry every 5 seconds
            } else {
                console.error('Failed to connect to Kafka after retries');
                process.exit(1); // Exit if Kafka connection fails after retries
            }
        }
    }
}

connectKafkaConsumer();

module.exports = {
    kafka,
    producer,
    consumer,
    connectKafka: async () => {
        try {
            await producer.connect();
            await consumer.connect();
            console.log('Connected to Kafka');
        } catch (error) {
            console.error('Failed to connect to Kafka:', error);
            process.exit(1);
        }
    }
};