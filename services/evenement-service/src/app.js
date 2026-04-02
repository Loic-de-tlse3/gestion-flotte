require('dotenv').config();

const express = require('express');
const app = express();
const port = Number(process.env.APP_PORT || 3004);
const { authenticate } = require('./middleware/authMiddleware');
const {
  startVehicleEventsConsumer,
  stopVehicleEventsConsumer,
} = require('./kafka/vehicleEventsConsumer');
const { disconnectProducer } = require('./kafka/producer');
const logger = require('./observability/logger');
const { httpLogger } = require('./observability/logger');

// Middleware
app.use(httpLogger); // Instrumentation HTTP automatique avec logs corrélés
app.use(express.json());

// Route de base
app.get('/', (req, res) => {
  logger.info({ service: 'evenement-service' }, 'Health check route accessed');
  res.send('Service Évènements - Microservice de gestion des évènements');
});

app.use((req, res, next) => {
  if (req.method === 'GET' && req.path === '/') {
    return next();
  }

  return authenticate(req, res, next);
});

let server;
let isShuttingDown = false;

const startConsumerWithRetry = async () => {
  if (isShuttingDown) {
    return;
  }

  try {
    await startVehicleEventsConsumer();
  } catch (error) {
    logger.error({ error: error.message }, '[Kafka] Consumer indisponible, nouvelle tentative dans 5s');
    setTimeout(startConsumerWithRetry, 5000);
  }
};

const start = async () => {
  server = app.listen(port, () => {
    logger.info({ port, service: 'evenement-service' }, 'Service Évènements démarré');
  });

  await startConsumerWithRetry();
};

const shutdown = async (signal) => {
  isShuttingDown = true;

  try {
    await stopVehicleEventsConsumer();
    await disconnectProducer();

    if (server) {
      server.close(() => {
        logger.info({ signal }, 'Service Évènements arrêté proprement');
        process.exit(0);
      });
      return;
    }

    process.exit(0);
  } catch (error) {
    logger.error({ error: error.message }, 'Erreur lors de l\'arrêt du consumer Kafka');
    process.exit(1);
  }
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

start();

