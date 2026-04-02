# Intégration Keycloak - Conducteur Service

Guide pour configurer et intégrer Keycloak pour l'authentification.

## 1) Configuration Keycloak (Admin Console)

### Créer le Realm

1. Aller sur `http://localhost:8080/admin` (ou votre URL Keycloak)
2. Login avec credentials Keycloak
3. Créer un nouveau realm : **`flotte-realm`**

### Créer le Client

1. Dans `flotte-realm`, aller à **Clients** → **Create**
2. Nommer le client : **`conducteur-service`**
3. Dans **Settings**:
   - **Client authentication**: ON
   - **Authentication flow**: Standard flow, Implicit flow, Direct access grants
4. Dans **Credentials** → copier le **Client Secret**
5. Dans **Client scopes** → Ajouter `email` et `profile`

### Créer les Rôles

1. **Menu** → **Realm roles** → **Create role**
   - `conducteur-admin`
   - `conducteur-manager`
   - `conducteur-viewer`

2. **Clients** → **conducteur-service** → **Client roles** → **Create role**
   - `read_drivers`
   - `write_drivers`
   - `manage_assignments`

### Créer des Utilisateurs Test

1. **Menu** → **Users** → **Add user**

   **Utilisateur 1 (Admin)**
   - Username: `admin`
   - Email: `admin@flotte.fr`
   - Set password: `admin123` (non-temporary)
   - Realm roles: `conducteur-admin`
   - Client roles (conducteur-service): `read_drivers`, `write_drivers`, `manage_assignments`

   **Utilisateur 2 (Manager)**
   - Username: `manager`
   - Email: `manager@flotte.fr`
   - Set password: `manager123` (non-temporary)
   - Realm roles: `conducteur-manager`
   - Client roles: `read_drivers`, `manage_assignments`

   **Utilisateur 3 (Viewer)**
   - Username: `viewer`
   - Email: `viewer@flotte.fr`
   - Set password: `viewer123` (non-temporary)
   - Client roles: `read_drivers`

---

## 2) Variables d'Environnement

Définir au lancement du service :

```bash
export KEYCLOAK_URL=http://localhost:8080
export KEYCLOAK_REALM=flotte-realm
export KEYCLOAK_CLIENT_ID=conducteur-service
export KEYCLOAK_CLIENT_SECRET=<votre-secret-genere>
```

Ou chaque fois que vous lancez le service :

```bash
cd services/conducteur-service
KEYCLOAK_URL=http://localhost:8080 \
KEYCLOAK_REALM=flotte-realm \
KEYCLOAK_CLIENT_ID=conducteur-service \
KEYCLOAK_CLIENT_SECRET=your-secret \
APP_PORT=3001 \
DATABASE_URL='postgresql://utilisateur_flotte:archi_distribuée@localhost:5432/flotte_db' \
npm run start
```

---

## 3) Obtenir un Token JWT

### Depuis Keycloak (Password Grant)

```bash
curl -X POST http://localhost:8080/realms/flotte-realm/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=conducteur-service" \
  -d "client_secret=your-client-secret" \
  -d "username=admin" \
  -d "password=admin123" \
  -d "grant_type=password"
```

**Réponse** (exemple) :
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cC...",
  "token_type": "Bearer",
  "expires_in": 300,
  "refresh_token": "..."
}
```

Extraire le token :

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/realms/flotte-realm/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=conducteur-service" \
  -d "client_secret=your-secret" \
  -d "username=admin" \
  -d "password=admin123" \
  -d "grant_type=password" | jq -r '.access_token')

echo $TOKEN
```

---

## 4) Utiliser le Token avec les Routes API

Toutes les routes **sauf** `GET /` nécessitent un token valide dans l'header `Authorization`.

### Créer un conducteur (authentifié)

```bash
TOKEN="votre-token-jwt"
curl -X POST http://localhost:3001/drivers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "keycloakId":"driver-123",
    "numeroPermis":"75PC123456",
    "telephone":"0612345678",
    "email":"driver@test.fr",
    "nom":"Dupont",
    "prenom":"Jean",
    "statutPermis":true,
    "categoriePermis":"B"
  }'
```

### Lister les conducteurs

```bash
curl -X GET http://localhost:3001/drivers \
  -H "Authorization: Bearer $TOKEN"
```

### Accès sans token (erreur 401)

```bash
curl -X GET http://localhost:3001/drivers
# Résultat: 401 Authentication failed
```

---

## 5) Script de Test Complet

```bash
#!/bin/bash

KEYCLOAK_URL="http://localhost:8080"
SERVICE_URL="http://localhost:3001"
REALM="flotte-realm"
CLIENT_ID="conducteur-service"
CLIENT_SECRET="your-client-secret"

echo "=== 1) Obtenir le token admin ==="
RESPONSE=$(curl -s -X POST $KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=admin" \
  -d "password=admin123" \
  -d "grant_type=password")

TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
echo "Token obtenu: ${TOKEN:0:50}..."

echo -e "\n=== 2) Créer un conducteur ==="
curl -X POST $SERVICE_URL/drivers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "keycloakId":"kc-test-'$(date +%s)'",
    "numeroPermis":"75PC'$(date +%s | tail -c 7)'",
    "telephone":"06'$(date +%s | tail -c 8)'",
    "email":"test@flotte.fr",
    "nom":"Test",
    "prenom":"User",
    "statutPermis":true,
    "categoriePermis":"B"
  }' | jq '.'

echo -e "\n=== 3) Lister les conducteurs ==="
curl -X GET $SERVICE_URL/drivers \
  -H "Authorization: Bearer $TOKEN" | jq '.'

echo -e "\n=== 4) Essayer sans token (erreur 401) ==="
curl -X GET $SERVICE_URL/drivers | jq '.'
```

---

## 6) Dépannage

### Token invalide ou expiré

```
401 Authentication failed: invalid signature
```

**Solutions** :
- Vérifier l'URL Keycloak (doit être accessible du service)
- Vérifier le nom du realm
- Invalider le cache des clés: redémarrer le service

### Client secret incorrect

```
401 Authentication failed: invalid_grant
```

**Solution** : Récupérer le bon client secret dans Keycloak Admin Console.

### JWKS URL inaccessible

```
Error: Unable to fetch Keycloak public keys
```

**Solutions** :
- Vérifier que Keycloak est accessible sur `KEYCLOAK_URL`
- Vérifier le `KEYCLOAK_REALM`
- Vérifier les pare-feu/réseau

---

## 7) Flux de Sécurité Expliqué

```
Client/Frontend
    ↓ (credentials: user + password)
    ↓
Keycloak Server (8080)
    ↓ (JWT access_token)
    ↓
Client reçoit Bearer token
    ↓ (Authorization: Bearer <token>)
    ↓
Conducteur Service (3001)
    ↓ (vérifie JWT signature)
    ↓ (utilise clés publiques Keycloak)
    ↓
Si valide → accès à la ressource
Si invalide → 401 Unauthorized
```

---

## 8) Code Source

- Configuration: [src/config/keycloak.js](src/config/keycloak.js)
- Middleware auth: [src/middleware/authMiddleware.js](src/middleware/authMiddleware.js)
- Routes protégées: [src/app.js](src/app.js)
