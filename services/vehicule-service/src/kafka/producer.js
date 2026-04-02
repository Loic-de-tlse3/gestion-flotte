const { randomUUID } = require('crypto');
const kafka = require('./client');

const topic = process.env.KAFKA_TOPIC_VEHICULES || 'vehicules';

const producer = kafka.producer();
let isConnected = false;

const ensureProducerConnected = async () => {
  if (!isConnected) {
    await producer.connect();
    isConnected = true;
  }
};

const publishVehicleEvent = async ({
  eventType,
  vehicle,
  payload,
  key,
  correlationId,
  causationId = null,
  entity = 'vehicule',
}) => {
  await ensureProducerConnected();

  const resolvedPayload = payload || vehicle;
  const eventId = randomUUID();
  const resolvedCorrelationId = correlationId || resolvedPayload?.maintenanceId || eventId;

  const event = {
    eventId,
    eventType,
    eventVersion: 1,
    entity,
    occurredAt: new Date().toISOString(),
    correlationId: resolvedCorrelationId,
    causationId,
    producer: 'vehicule-service',
    payload: resolvedPayload,
  };

  await producer.send({
    topic,
    messages: [
      {
        key: key || resolvedPayload?.id || resolvedPayload?.vehicleId || resolvedPayload?.maintenanceId || eventId,
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
  publishVehicleEvent,
  disconnectProducer,
};