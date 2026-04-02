require('dotenv').config();

const express = require('express');
const cors = require('cors');
const conducteurController = require('./controllers/conducteurController');
const {
  validateConducteurId,
  validateConducteurPayload,
} = require('./middleware/conducteurValidation');
const {
  validateAssignmentId,
  validateAssignmentPayload,
  validateAssignmentClosePayload,
} = require('./middleware/assignmentValidation');
const { authenticate, authorize } = require('./middleware/authMiddleware');
const {
  startVehicleAssignmentEventsConsumer,
  stopVehicleAssignmentEventsConsumer,
} = require('./kafka/vehicleAssignmentEventsConsumer');
const { disconnectProducer } = require('./kafka/producer');

const app = express();
const port = Number(process.env.APP_PORT || 3001);

// Middleware
app.use(express.json());
app.use(cors());

// Route de base
app.get('/', (req, res) => {
  res.send('Service Conducteur - Microservice de gestion des conducteurs');
});

const READ_ROLES = ['Admin', 'Conducteur', 'Technicien'];
const WRITE_ROLES = ['Admin', 'Technicien'];

// Toutes les routes sauf '/' nécessitent l'authentification Keycloak
app.use('/drivers', authenticate);
app.use('/assignments', authenticate);

// CRUD Conducteurs
app.get('/drivers', authorize(...READ_ROLES), conducteurController.getConducteurs);
app.post('/drivers', authorize(...WRITE_ROLES), validateConducteurPayload, conducteurController.createConducteur);
app.get('/drivers/:id', authorize(...READ_ROLES), validateConducteurId, conducteurController.getConducteurById);
app.put('/drivers/:id', authorize(...WRITE_ROLES), validateConducteurId, validateConducteurPayload, conducteurController.updateConducteur);
app.delete('/drivers/:id', authorize(...WRITE_ROLES), validateConducteurId, conducteurController.deleteConducteur);

// Assignations
app.get('/drivers/:id/assignments', authorize(...READ_ROLES), validateConducteurId, conducteurController.getAssignmentsByDriver);
app.post('/drivers/:id/assignments', authorize(...WRITE_ROLES), validateConducteurId, validateAssignmentPayload, conducteurController.createAssignmentForDriver);
app.put('/assignments/:assignmentId/end', authorize(...WRITE_ROLES), validateAssignmentId, validateAssignmentClosePayload, conducteurController.closeAssignment);

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
    await startVehicleAssignmentEventsConsumer();
  } catch (error) {
    console.error('[Kafka] Consumer indisponible, nouvelle tentative dans 5s:', error.message);
    setTimeout(startConsumerWithRetry, 5000);
  }
};

const start = async () => {
  server = app.listen(port, () => {
    console.log(`Service Conducteur démarré sur le port ${port}`);
  });

  await startConsumerWithRetry();
};

const shutdown = async (signal) => {
  isShuttingDown = true;

  try {
    await stopVehicleAssignmentEventsConsumer();
    await disconnectProducer();

    if (server) {
      server.close(() => {
        console.log(`Service Conducteur arrêté proprement (${signal})`);
        process.exit(0);
      });
      return;
    }

    process.exit(0);
  } catch (error) {
    console.error('Erreur lors de l\'arrêt du service Conducteur:', error.message);
    process.exit(1);
  }
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

start();

