const { randomUUID } = require('crypto');
const kafka = require('./client');

const topic = process.env.KAFKA_TOPIC_MAINTENANCES || 'maintenances';

const producer = kafka.producer();
let isConnected = false;

const ensureProducerConnected = async () => {
  if (!isConnected) {
    await producer.connect();
    isConnected = true;
  }
};

const publishMaintenanceEvent = async ({
  eventType,
  payload,
  key,
  entity = 'maintenance',
  correlationId,
  causationId = null,
}) => {
  await ensureProducerConnected();

  const eventId = randomUUID();
  const resolvedCorrelationId = correlationId || payload?.maintenanceId || eventId;

  const event = {
    eventId,
    eventType,
    eventVersion: 1,
    occurredAt: new Date().toISOString(),
    entity,
    correlationId: resolvedCorrelationId,
    causationId,
    producer: 'maintenance-service',
    payload,
  };

  await producer.send({
    topic,
    messages: [
      {
        key: key || payload?.maintenanceId || eventId,
        value: JSON.stringify(event),
      },
    ],
  });
};

const disconnectProducer = async () => {
  if (isConnected) {
    await producer.disconnect();
    isConnected = false;
  }
};

module.exports = {
  publishMaintenanceEvent,
  disconnectProducer,
};
