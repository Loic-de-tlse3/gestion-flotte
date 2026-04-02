const { randomUUID } = require('crypto');
const kafka = require('./client');

const topic = process.env.KAFKA_TOPIC_CONDUCTEURS || 'conducteurs';

const producer = kafka.producer();
let isConnected = false;

const ensureProducerConnected = async () => {
  if (!isConnected) {
    await producer.connect();
    isConnected = true;
  }
};

const publishConducteurEvent = async ({
  eventType,
  conducteur,
  payload,
  key,
  correlationId,
  causationId = null,
  entity = 'conducteur',
}) => {
  await ensureProducerConnected();

  const resolvedPayload = payload || conducteur;
  const eventId = randomUUID();
  const resolvedCorrelationId = correlationId || resolvedPayload?.assignmentId || resolvedPayload?.id || eventId;

  const event = {
    eventId,
    eventType,
    eventVersion: 1,
    entity,
    occurredAt: new Date().toISOString(),
    correlationId: resolvedCorrelationId,
    causationId,
    producer: 'conducteur-service',
    payload: resolvedPayload,
  };

  await producer.send({
    topic,
    messages: [
      {
        key: key || resolvedPayload?.assignmentId || resolvedPayload?.id || eventId,
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
  publishConducteurEvent,
  disconnectProducer,
};