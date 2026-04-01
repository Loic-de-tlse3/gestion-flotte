/**
 * Middleware d'authentification JWT Keycloak
 */

const jwt = require('jsonwebtoken');
const axios = require('axios');

const KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://localhost:8080';
const KEYCLOAK_REALM = process.env.KEYCLOAK_REALM || 'flotte-realm';
const JWKS_URL = `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs`;

let cachedKeys = null;
let keysFetchedAt = 0;
const CACHE_DURATION = 3600000;

async function getPublicKeys() {
  const now = Date.now();

  if (cachedKeys && (now - keysFetchedAt) < CACHE_DURATION) {
    return cachedKeys;
  }

  const response = await axios.get(JWKS_URL);
  cachedKeys = response.data.keys;
  keysFetchedAt = now;
  return cachedKeys;
}

function getSigningKey(header, keys) {
  const key = keys.find((item) => item.kid === header.kid);

  if (!key) {
    throw new Error('Unable to find matching key');
  }

  return `-----BEGIN CERTIFICATE-----\n${key.x5c[0]}\n-----END CERTIFICATE-----`;
}

async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;

  if (req.originalUrl === '/' && req.method === 'GET') {
    return next();
  }

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      message: 'Authentication failed',
      error: 'Missing or invalid Authorization header',
    });
  }

  const token = authHeader.slice(7);

  try {
    const keys = await getPublicKeys();
    const decoded = jwt.decode(token, { complete: true });

    if (!decoded) {
      throw new Error('Invalid token format');
    }

    const signingKey = getSigningKey(decoded.header, keys);
    const verified = jwt.verify(token, signingKey, {
      issuer: `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}`,
      audience: ['account', process.env.KEYCLOAK_CLIENT_ID || 'Service-conducteurs'],
    });

    req.user = {
      id: verified.sub,
      roles: verified.realm_access?.roles || [],
      clientRoles: verified.resource_access?.[process.env.KEYCLOAK_CLIENT_ID || 'Service-conducteurs']?.roles || [],
    };

    return next();
  } catch (error) {
    return res.status(401).json({
      message: 'Authentication failed',
      error: error.message,
    });
  }
}

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

    return next();
  };
}

module.exports = {
  authenticate,
  authorize,
};
