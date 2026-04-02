require('dotenv').config();

const express = require('express');
const app = express();
const port = Number(process.env.APP_PORT || 3002);
const { authenticate } = require('./middleware/authMiddleware');
const maintenanceController = require('./controllers/maintenanceController');
const {
  startVehicleEventsConsumer,
  stopVehicleEventsConsumer,
} = require('./kafka/vehicleEventsConsumer');
const { disconnectProducer } = require('./kafka/producer');

// Middleware
app.use(express.json());

// Route de base
app.get('/', (req, res) => {
  res.send('Service Maintenance - Microservice de gestion des maintenance');
});

app.use((req, res, next) => {
  if (req.method === 'GET' && req.path === '/') {
    return next();
  }

  return authenticate(req, res, next);
});

app.post('/maintenances', maintenanceController.createMaintenance);
app.get('/maintenances/:id', maintenanceController.getMaintenanceById);
app.get('/maintenances', maintenanceController.listMaintenances);

app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

app.use((err, req, res, next) => {
  const status = err.status || 500;
  res.status(status).json({
    message: err.message || 'Internal server error',
  });
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
    console.error('[Kafka] Consumer indisponible, nouvelle tentative dans 5s:', error.message);
    setTimeout(startConsumerWithRetry, 5000);
  }
};

const start = async () => {
  server = app.listen(port, () => {
    console.log(`Service Maintenance démarré sur le port ${port}`);
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
        console.log(`Service Maintenance arrêté proprement (${signal})`);
        process.exit(0);
      });
      return;
    }

    process.exit(0);
  } catch (error) {
    console.error('Erreur lors de l\'arrêt du service Maintenance:', error.message);
    process.exit(1);
  }
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

start();

