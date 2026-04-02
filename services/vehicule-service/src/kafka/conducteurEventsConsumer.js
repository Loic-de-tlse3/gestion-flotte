const kafka = require('./client');
const vehicleService = require('../services/vehicleService');

const topic = process.env.KAFKA_TOPIC_CONDUCTEURS || 'conducteurs';
const groupId = process.env.KAFKA_CONDUCTEUR_GROUP_ID || 'vehicule-service-conducteur-group';

const consumer = kafka.consumer({ groupId });
let started = false;

const startConducteurEventsConsumer = async () => {
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

        if (event.eventType !== 'conducteur.affectation_demandee') {
          return;
        }

        await vehicleService.handleAssignmentDemand(event);
      } catch (error) {
        console.error('[Kafka] Message conducteur invalide ou non traitable:', error.message);
      }
    },
  });

  started = true;
  console.log(`[Kafka] Véhicule consumer connecté au topic "${topic}" (group: ${groupId})`);
};

const stopConducteurEventsConsumer = async () => {
  if (!started) {
    return;
  }

  await consumer.disconnect();
  started = false;
};

module.exports = {
  startConducteurEventsConsumer,
  stopConducteurEventsConsumer,
};
