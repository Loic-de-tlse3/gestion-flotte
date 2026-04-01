require('dotenv').config();

const express = require('express');
const app = express();
const port = 3003;
const { authenticate } = require('./middleware/authMiddleware');

// Middleware
app.use(express.json());

// Route de base
app.get('/', (req, res) => {
  res.send('Service Localisations - Microservice de gestion des localisations');
});

app.use((req, res, next) => {
  if (req.method === 'GET' && req.path === '/') {
    return next();
  }

  return authenticate(req, res, next);
});

// Démarrage du serveur
app.listen(port, () => {
  console.log(`Service Localisation démarré sur le port ${port}`);
});

