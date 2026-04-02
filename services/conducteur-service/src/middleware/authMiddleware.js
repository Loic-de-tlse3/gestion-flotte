/**
 * Middleware d'authentification JWT Keycloak
 * Vérifie et décode le token JWT du header Authorization
 */

const jwt = require('jsonwebtoken');
const axios = require('axios');

const KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://localhost:8080';
const KEYCLOAK_REALM = process.env.KEYCLOAK_REALM || 'flotte-realm';
const JWKS_URL = `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs`;

let cachedKeys = null;
let keysFetchedAt = 0;
const CACHE_DURATION = 3600000; // 1 heure

/**
 * Récupère les clé publique depuis Keycloak
 */
async function getPublicKeys() {
  const now = Date.now();
  
  // Retour cache si disponible
  if (cachedKeys && (now - keysFetchedAt) < CACHE_DURATION) {
    return cachedKeys;
  }

  try {
    const response = await axios.get(JWKS_URL);
    cachedKeys = response.data.keys;
    keysFetchedAt = now;
    return cachedKeys;
  } catch (error) {
    console.error('Erreur lors de la récupération des clés Keycloak:', error.message);
    throw new Error('Unable to fetch Keycloak public keys');
  }
}

/**
 * Récupère la clé publique pour vérifier le JWT
 */
function getSigningKey(header, keys) {
  const key = keys.find((k) => k.kid === header.kid);
  if (!key) {
    throw new Error('Unable to find matching key');
  }
  
  const cert = `-----BEGIN CERTIFICATE-----\n${key.x5c[0]}\n-----END CERTIFICATE-----`;
  return cert;
}

/**
 * Middleware d'authentification
 */
async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  
  // Route publique : health check
  if (req.originalUrl === '/' && req.method === 'GET') {
    return next();
  }

  if (process.env.TEST_MODE === 'true') {
    req.user = {
      id: 'test-user',
      roles: ['Admin', 'Conducteur'],
      clientRoles: ['Admin', 'Conducteur'],
    };
    return next();
  }

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      message: 'Authentication failed',
      error: 'Missing or invalid Authorization header',
    });
  }

  const token = authHeader.substring(7);

  try {
    // Récupère les clés publiques
    const keys = await getPublicKeys();
    
    // Décorre le header sans vérification
    const decoded = jwt.decode(token, { complete: true });
    if (!decoded) {
      throw new Error('Invalid token format');
    }

    // Récupère la clé de signature
    const signingKey = getSigningKey(decoded.header, keys);

    // Vérifie et décorde le token
    const verified = jwt.verify(token, signingKey, {
      issuer: `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}`,
      audience: ['account', process.env.KEYCLOAK_CLIENT_ID || 'conducteur-service'],
    });

    // Attache l'utilisateur à la requête
    req.user = {
      id: verified.sub,
      keycloakId: verified.sub,
      username: verified.preferred_username,
      email: verified.email,
      roles: verified.realm_access?.roles || [],
      clientRoles: verified.resource_access?.[process.env.KEYCLOAK_CLIENT_ID || 'conducteur-service']?.roles || [],
    };

    next();
  } catch (error) {
    console.error('Erreur de vérification du token:', error.message);
    return res.status(401).json({
      message: 'Authentication failed',
      error: error.message,
    });
  }
}

/**
 * Middleware pour vérifier les rôles
 */
function authorize(...requiredRoles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ message: 'Authentication required' });
    }

    const userRoles = [...req.user.roles, ...req.user.clientRoles];
    const hasRole = requiredRoles.some((role) => userRoles.includes(role));

    if (!hasRole) {
      return res.status(403).json({
        message: 'Authorization failed',
        error: `Required roles: ${requiredRoles.join(', ')}`,
      });
    }

    next();
  };
}

module.exports = {
  authenticate,
  authorize,
};
