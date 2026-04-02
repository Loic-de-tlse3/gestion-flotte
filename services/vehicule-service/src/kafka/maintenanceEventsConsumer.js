const kafka = require('./client');
const vehicleService = require('../services/vehicleService');

const topic = process.env.KAFKA_TOPIC_MAINTENANCES || 'maintenances';
const groupId = process.env.KAFKA_MAINTENANCE_GROUP_ID || 'vehicule-service-maintenance-group';

const consumer = kafka.consumer({ groupId });
let started = false;

const startMaintenanceEventsConsumer = async () => {
  if (started) {
    return;
  }

  await consumer.connect();
  await consumer.subscribe({ topic, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) {
        return;
      }

      try {
        const event = JSON.parse(message.value.toString());

        if (event.eventType !== 'maintenance.demandee') {
          return;
        }

        await vehicleService.handleMaintenanceDemand(event);
      } catch (error) {
        console.error('[Kafka] Message maintenance invalide ou non traitable:', error.message);
      }
    },
  });

  started = true;
  console.log(`[Kafka] Véhicule consumer connecté au topic "${topic}" (group: ${groupId})`);
};

const stopMaintenanceEventsConsumer = async () => {
  if (!started) {
    return;
  }

  await consumer.disconnect();
  started = false;
};

module.exports = {
  startMaintenanceEventsConsumer,
  stopMaintenanceEventsConsumer,
};
