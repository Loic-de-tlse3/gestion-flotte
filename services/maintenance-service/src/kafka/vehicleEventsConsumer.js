const kafka = require('./client');
const maintenanceService = require('../services/maintenanceService');

const topic = process.env.KAFKA_TOPIC_VEHICULES || 'vehicules';
const groupId = process.env.KAFKA_GROUP_ID || 'maintenance-service-group';

const consumer = kafka.consumer({ groupId });
let started = false;

const handledEventTypes = new Set([
  'vehicule.immobilise',
  'vehicule.maintenance_planifiee_sans_immobilisation',
  'vehicule.immobilisation_echouee',
]);

const startVehicleEventsConsumer = async () => {
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

        if (!handledEventTypes.has(event.eventType)) {
          return;
        }

        await maintenanceService.handleVehicleEvent(event);
      } catch (error) {
        console.error('[Kafka] Message véhicule invalide ou non traitable:', error.message);
      }
    },
  });

  started = true;
  console.log(`[Kafka] Maintenance consumer connecté au topic "${topic}" (group: ${groupId})`);
};

const stopVehicleEventsConsumer = async () => {
  if (!started) {
    return;
  }

  await consumer.disconnect();
  started = false;
};

module.exports = {
  startVehicleEventsConsumer,
  stopVehicleEventsConsumer,
};
