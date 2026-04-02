const kafka = require('./client');
const { publishAlertEvent } = require('./producer');

const vehicleTopic = process.env.KAFKA_TOPIC_VEHICULES || 'vehicules';
const maintenanceTopic = process.env.KAFKA_TOPIC_MAINTENANCES || 'maintenances';
const conducteurTopic = process.env.KAFKA_TOPIC_CONDUCTEURS || 'conducteurs';
const groupId = process.env.KAFKA_GROUP_ID || 'evenement-service-group';

const consumer = kafka.consumer({ groupId });
let started = false;

const startVehicleEventsConsumer = async () => {
  if (started) {
    return;
  }

  await consumer.connect();
  await consumer.subscribe({ topic: vehicleTopic, fromBeginning: false });
  await consumer.subscribe({ topic: maintenanceTopic, fromBeginning: false });
  await consumer.subscribe({ topic: conducteurTopic, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) {
        return;
      }

      try {
        const event = JSON.parse(message.value.toString());
        console.log('[Kafka] Événement reçu:', event.eventType, event.payload?.id || 'sans-id');

        if (event.eventType === 'vehicule.immobilisation_echouee') {
          await publishAlertEvent({
            correlationId: event.correlationId || event.payload?.maintenanceId,
            causationId: event.eventId,
            severity: 'HIGH',
            message: event.payload?.reasonMessage || 'Échec d\'immobilisation véhicule',
          });
        }

        if (event.eventType === 'maintenance.annulee') {
          await publishAlertEvent({
            correlationId: event.correlationId || event.payload?.maintenanceId,
            causationId: event.eventId,
            severity: 'HIGH',
            message: `Maintenance annulée (${event.payload?.reasonCode || 'UNKNOWN_REASON'})`,
          });
        }

        if (event.eventType === 'conducteur.affectation_annulee') {
          await publishAlertEvent({
            correlationId: event.correlationId || event.payload?.assignmentId,
            causationId: event.eventId,
            severity: 'MEDIUM',
            message: `Affectation annulée (${event.payload?.reasonCode || 'VEHICLE_NOT_AVAILABLE'})`,
          });
        }
      } catch (error) {
        console.error('[Kafka] Message invalide:', error.message);
      }
    },
  });

  started = true;
  console.log(`[Kafka] Consumer connecté aux topics "${vehicleTopic}", "${maintenanceTopic}" et "${conducteurTopic}" (group: ${groupId})`);
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