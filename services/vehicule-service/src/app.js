require('dotenv').config();

const express = require('express');
const cors = require('cors');
const vehicleController = require('./controllers/vehicleController');
const {
  validateVehicleId,
  validateVehiclePayload,
} = require('./middleware/vehicleValidation');
const { authenticate, authorize } = require('./middleware/authMiddleware');
const { disconnectProducer } = require('./kafka/producer');
const logger = require('./observability/logger');
const { httpLogger } = require('./observability/logger');

const app = express();
const port = 3000;
const READ_ROLES = ['Admin', 'Conducteur', 'Technicien'];
const WRITE_ROLES = ['Admin', 'Technicien'];

// Middleware
app.use(httpLogger); // Instrumentation HTTP automatique avec logs corrélés
app.use(express.json());
app.use(cors());

// Route de base
app.get('/', (req, res) => {
  logger.info({ service: 'vehicule-service' }, 'Health check route accessed');
  res.send('Service Véhicules - Microservice de gestion des véhicules');
});

app.use('/vehicles', authenticate);

// CRUD Véhicules
app.get('/vehicles', authorize(...READ_ROLES), vehicleController.getVehicles);
app.post('/vehicles', authorize(...WRITE_ROLES), validateVehiclePayload, vehicleController.createVehicle);
app.get('/vehicles/:id', authorize(...READ_ROLES), validateVehicleId, vehicleController.getVehicleById);
app.put('/vehicles/:id', authorize(...WRITE_ROLES), validateVehicleId, validateVehiclePayload, vehicleController.updateVehicle);
app.delete('/vehicles/:id', authorize(...WRITE_ROLES), validateVehicleId, vehicleController.deleteVehicle);

app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

app.use((err, req, res, next) => {
  const status = err.status || 500;
  res.status(status).json({
    message: err.message || 'Internal server error',
  });
});

// Démarrage du serveur
app.listen(port, () => {
  logger.info({ port, service: 'vehicule-service' }, 'Service Véhicules démarré');
});

const shutdown = async (signal) => {
  try {
    await disconnectProducer();
    logger.info({ signal }, 'Service Véhicules arrêté proprement');
    process.exit(0);
  } catch (error) {
    logger.error({ signal, error: error.message }, 'Erreur lors de l\'arrêt du producer Kafka');
    process.exit(1);
  }
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

