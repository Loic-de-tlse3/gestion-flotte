# Tests Keycloak — Vérification rapide

Ce guide permet de vérifier que l’authentification + autorisation Keycloak fonctionne sur les microservices.

---

## Prérequis
- Keycloak démarré sur `http://localhost:8080`
- Realm: `FleetManagement`
- Client: `Service-conducteurs`
- Utilisateur de test existant (ex: `admin_test`) avec mot de passe
- Services démarrés (`conducteur`, `vehicule`, etc.)
- `jq` installé

---

## 1) Récupérer un token JWT

```bash
KC_URL="http://localhost:8080"
KC_REALM="FleetManagement"
KC_CLIENT_ID="Service-conducteurs"
KC_CLIENT_SECRET="<CLIENT_SECRET>"
KC_USERNAME="admin_test"
KC_PASSWORD="<PASSWORD>"

TOKEN=$(curl -s -X POST "$KC_URL/realms/$KC_REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$KC_CLIENT_ID" \
  -d "client_secret=$KC_CLIENT_SECRET" \
  -d "username=$KC_USERNAME" \
  -d "password=$KC_PASSWORD" \
  -d "grant_type=password" | jq -r '.access_token')

echo "$TOKEN"
```

Attendu: token non vide (et non `null`).

---

## 2) Test auth — sans token (doit échouer)

```bash
curl -s -o /tmp/noauth.txt -w '%{http_code}\n' http://localhost:3006/drivers
```

Attendu: `401`

---

## 3) Test auth — avec token (doit passer)

```bash
curl -s -o /tmp/auth.txt -w '%{http_code}\n' \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:3006/drivers
```

Attendu: `200`

---

## 4) Test RBAC lecture

```bash
curl -s -o /tmp/rbac_read.txt -w '%{http_code}\n' \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/vehicles
```

Attendu:
- `200` si rôle `Admin|Conducteur|Technicien`
- `403` sinon

---

## 5) Test RBAC écriture

```bash
curl -s -o /tmp/rbac_write.txt -w '%{http_code}\n' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"immatriculation":"AA-123-BB","marque":"Renault","modele":"Clio","statut":"AVAILABLE"}' \
  http://localhost:3000/vehicles
```

Attendu:
- `201` (ou `200` selon implémentation) si rôle `Admin|Technicien`
- `403` si rôle `Conducteur`

Valeurs valides pour `statut`:
- `AVAILABLE`
- `IN_USE`
- `MAINTENANCE`
- `RETIRED`

---

## 6) Vérification service événement

```bash
# Public
curl -s -o /tmp/evt_root.txt -w '%{http_code}\n' http://localhost:3004/

# Protégé
curl -s -o /tmp/evt_private.txt -w '%{http_code}\n' http://localhost:3004/private-test
```

Attendu:
- `GET /` => `200`
- route non-root sans token => `401`

---

## 7) Debug rapide

### Token vide / null
```bash
curl -s -X POST "$KC_URL/realms/$KC_REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$KC_CLIENT_ID" \
  -d "client_secret=$KC_CLIENT_SECRET" \
  -d "username=$KC_USERNAME" \
  -d "password=$KC_PASSWORD" \
  -d "grant_type=password" | jq .
```

### Vérifier les claims du token
```bash
echo "$TOKEN" | awk -F. '{print $2}' | base64 -d 2>/dev/null | jq .
```

### Vérifier que l’utilisateur a bien les rôles
- Keycloak Admin Console → `Users` → utilisateur → `Role mapping`

---

## Checklist finale (OK/KO)
- [ ] Token récupéré
- [ ] `401` sans token
- [ ] `200` avec token sur une route de lecture
- [ ] `403` quand rôle insuffisant
- [ ] `200/201` quand rôle adéquat
