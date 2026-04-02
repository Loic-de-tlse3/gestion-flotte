const { randomUUID } = require('crypto');
const kafka = require('./client');

const topic = process.env.KAFKA_TOPIC_ALERTES || 'alertes';

const producer = kafka.producer();
let isConnected = false;

const ensureProducerConnected = async () => {
  if (!isConnected) {
    await producer.connect();
    isConnected = true;
  }
};

const publishAlertEvent = async ({ correlationId, causationId, severity = 'HIGH', message }) => {
  await ensureProducerConnected();

  const eventId = randomUUID();
  const payload = {
    sagaId: correlationId,
    severity,
    message,
  };

  const event = {
    eventId,
    eventType: 'alerte.creee',
    eventVersion: 1,
    occurredAt: new Date().toISOString(),
    entity: 'alerte',
    correlationId,
    causationId,
    producer: 'evenement-service',
    payload,
  };

  await producer.send({
    topic,
    messages: [{
      key: correlationId || eventId,
      value: JSON.stringify(event),
    }],
  });
};

const disconnectProducer = async () => {
  if (isConnected) {
    await producer.disconnect();
    isConnected = false;
  }
};

module.exports = {
  publishAlertEvent,
  disconnectProducer,
};
