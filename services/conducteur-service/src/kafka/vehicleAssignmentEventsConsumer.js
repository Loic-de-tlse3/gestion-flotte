const kafka = require('./client');
const conducteurService = require('../services/conducteurService');

const topic = process.env.KAFKA_TOPIC_VEHICULES || 'vehicules';
const groupId = process.env.KAFKA_ASSIGNMENT_GROUP_ID || 'conducteur-service-assignment-group';

const consumer = kafka.consumer({ groupId });
let started = false;

const handledEventTypes = new Set([
  'vehicule.affectation_acceptee',
  'vehicule.affectation_refusee',
]);

const startVehicleAssignmentEventsConsumer = async () => {
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

        await conducteurService.handleVehicleAssignmentEvent(event);
      } catch (error) {
        console.error('[Kafka] Message véhicule invalide ou non traitable:', error.message);
      }
    },
  });

  started = true;
  console.log(`[Kafka] Conducteur consumer connecté au topic "${topic}" (group: ${groupId})`);
};

const stopVehicleAssignmentEventsConsumer = async () => {
  if (!started) {
    return;
  }

  await consumer.disconnect();
  started = false;
};

module.exports = {
  startVehicleAssignmentEventsConsumer,
  stopVehicleAssignmentEventsConsumer,
};
