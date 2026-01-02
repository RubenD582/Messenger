// kafkaClient.js
const { Kafka, Partitioners } = require('kafkajs');

const kafka = new Kafka({
    brokers: [process.env.KAFKA_BROKER || 'localhost:29092'],
    clientId: 'messenger-app',
});
  

// Create shared producer instance
const producer = kafka.producer({
    createPartitioner: Partitioners.LegacyPartitioner,
});

// Create shared consumer instance for friend events
const consumer = kafka.consumer({ groupId: 'friend-events-group' });

// Create consumer instances for chat system
const messageConsumer = kafka.consumer({ groupId: 'message-delivery-group' });
const typingConsumer = kafka.consumer({ groupId: 'typing-broadcast-group' });
const receiptConsumer = kafka.consumer({ groupId: 'receipt-update-group' });



module.exports = {
    kafka,
    producer,
    consumer,
    messageConsumer,
    typingConsumer,
    receiptConsumer,
    connectKafka: async () => {
        try {
            await producer.connect();
            await consumer.connect();
            await messageConsumer.connect();
            await typingConsumer.connect();
            await receiptConsumer.connect();
            console.log('Connected to Kafka (all producers and consumers)');
        } catch (error) {
            console.error('Failed to connect to Kafka:', error);
            process.exit(1);
        }
    }
};