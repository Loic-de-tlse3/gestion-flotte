#!/bin/bash
set -euo pipefail

WORKSPACE='/home/loic/Documents/Fac/Architecture distribuée/gestion-de-flotte-automobile-main'
cd "$WORKSPACE"

MODE="${1:-test}" # test | auth

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VEHICULE_PORT=3100
CONDUCTEUR_PORT=3101
MAINTENANCE_PORT=3102
EVENEMENT_PORT=3104
KEYCLOAK_PORT=18080

auth_args=()

cleanup() {
  echo ""
  echo "🛑 Arrêt des services et de l'infra..."

  [[ -n "${VEHICULE_PID:-}" ]] && kill -9 "$VEHICULE_PID" 2>/dev/null || true
  [[ -n "${MAINTENANCE_PID:-}" ]] && kill -9 "$MAINTENANCE_PID" 2>/dev/null || true
  [[ -n "${EVENEMENT_PID:-}" ]] && kill -9 "$EVENEMENT_PID" 2>/dev/null || true
  [[ -n "${CONDUCTEUR_PID:-}" ]] && kill -9 "$CONDUCTEUR_PID" 2>/dev/null || true

  docker rm -f e2e-postgres e2e-keycloak >/dev/null 2>&1 || true
  docker-compose -f helm/infra/docker-compose.kafka.yml down >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_kafka() {
  echo -e "${BLUE}[1/5] Démarrage de Kafka...${NC}"
  docker-compose -f helm/infra/docker-compose.kafka.yml up -d >/dev/null
  sleep 8
  echo -e "${GREEN}✓ Kafka démarré${NC}"
  echo ""
}

start_postgres() {
  echo -e "${BLUE}[2/5] Démarrage PostgreSQL de test...${NC}"
  docker rm -f e2e-postgres >/dev/null 2>&1 || true
  docker run -d --name e2e-postgres \
    -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=fleet \
    -p 55432:5432 postgres:16-alpine >/dev/null

  for i in {1..40}; do
    if docker exec e2e-postgres pg_isready -U postgres -d fleet >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  docker exec -i e2e-postgres psql -U postgres -d fleet >/dev/null <<'SQL'
CREATE SCHEMA IF NOT EXISTS service_vehicles;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_status_enum') THEN
    CREATE TYPE vehicle_status_enum AS ENUM ('AVAILABLE','IN_USE','MAINTENANCE','RETIRED');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS service_vehicles.vehicles (
  id UUID PRIMARY KEY,
  immatriculation VARCHAR(20) NOT NULL UNIQUE,
  marque VARCHAR(100) NOT NULL,
  "modèle" VARCHAR(100) NOT NULL,
  statut vehicle_status_enum NOT NULL DEFAULT 'AVAILABLE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE SCHEMA IF NOT EXISTS service_conducteurs;

CREATE TABLE IF NOT EXISTS service_conducteurs.drivers (
  id UUID PRIMARY KEY,
  keycloak_id VARCHAR(255) NOT NULL,
  "numéro_permis" VARCHAR(50) NOT NULL,
  nom VARCHAR(100) NOT NULL,
  "prénom" VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  "téléphone" VARCHAR(20) NOT NULL,
  statut_permis BOOLEAN NOT NULL DEFAULT true,
  categorie_permis VARCHAR(10),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uk_drivers_keycloak_id'
      AND conrelid = 'service_conducteurs.drivers'::regclass
  ) THEN
    ALTER TABLE service_conducteurs.drivers
      ADD CONSTRAINT uk_drivers_keycloak_id UNIQUE (keycloak_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uk_drivers_numero_permis'
      AND conrelid = 'service_conducteurs.drivers'::regclass
  ) THEN
    ALTER TABLE service_conducteurs.drivers
      ADD CONSTRAINT uk_drivers_numero_permis UNIQUE ("numéro_permis");
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uk_drivers_telephone'
      AND conrelid = 'service_conducteurs.drivers'::regclass
  ) THEN
    ALTER TABLE service_conducteurs.drivers
      ADD CONSTRAINT uk_drivers_telephone UNIQUE ("téléphone");
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS service_conducteurs.assignments (
  id UUID PRIMARY KEY,
  driver_id UUID NOT NULL,
  vehicle_id UUID NOT NULL,
  "date_début" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_fin TIMESTAMPTZ,
  motif TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_assignments_date CHECK (date_fin IS NULL OR date_fin > "date_début")
);
SQL
  echo -e "${GREEN}✓ PostgreSQL de test prêt${NC}"
  echo ""
}

setup_keycloak_auth_mode() {
  echo -e "${BLUE}[3/5] Préparation Keycloak (mode auth)...${NC}"
  docker rm -f e2e-keycloak >/dev/null 2>&1 || true
  docker run -d --name e2e-keycloak \
    -p ${KEYCLOAK_PORT}:8080 \
    -e KEYCLOAK_ADMIN=admin \
    -e KEYCLOAK_ADMIN_PASSWORD=admin \
    quay.io/keycloak/keycloak:latest start-dev >/dev/null

  for i in {1..90}; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${KEYCLOAK_PORT}/realms/master/.well-known/openid-configuration" || true)
    [[ "$code" == "200" ]] && break
    sleep 2
  done

  ADM=$(curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/realms/master/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=admin-cli' \
    -d 'username=admin' \
    -d 'password=admin' \
    -d 'grant_type=password' | jq -r '.access_token')

  [[ -n "$ADM" && "$ADM" != "null" ]]

  curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/admin/realms" \
    -H "Authorization: Bearer $ADM" -H 'Content-Type: application/json' \
    -d '{"realm":"FleetManagement","enabled":true}' >/dev/null || true

  for role in Admin Technicien Conducteur; do
    curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/roles" \
      -H "Authorization: Bearer $ADM" -H 'Content-Type: application/json' \
      -d "{\"name\":\"$role\"}" >/dev/null || true
  done

  curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/clients" \
    -H "Authorization: Bearer $ADM" -H 'Content-Type: application/json' \
    -d '{"clientId":"Service-conducteurs","enabled":true,"publicClient":false,"serviceAccountsEnabled":true,"directAccessGrantsEnabled":false,"standardFlowEnabled":false,"implicitFlowEnabled":false,"protocol":"openid-connect"}' >/dev/null || true

  CID=$(curl -s -H "Authorization: Bearer $ADM" "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/clients?clientId=Service-conducteurs" | jq -r '.[0].id')
  SECRET=$(curl -s -H "Authorization: Bearer $ADM" "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/clients/$CID/client-secret" | jq -r '.value')
  SERVICE_USER_ID=$(curl -s -H "Authorization: Bearer $ADM" "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/clients/$CID/service-account-user" | jq -r '.id')

  for role in Admin Technicien Conducteur; do
    role_json=$(curl -s -H "Authorization: Bearer $ADM" "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/roles/$role")
    curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/admin/realms/FleetManagement/users/$SERVICE_USER_ID/role-mappings/realm" \
      -H "Authorization: Bearer $ADM" -H 'Content-Type: application/json' \
      -d "[$role_json]" >/dev/null || true
  done

  TOKEN=$(curl -s -X POST "http://localhost:${KEYCLOAK_PORT}/realms/FleetManagement/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=Service-conducteurs' \
    -d "client_secret=$SECRET" \
    -d 'grant_type=client_credentials' | jq -r '.access_token')

  [[ -n "$TOKEN" && "$TOKEN" != "null" ]]
  AUTH_HEADER="Authorization: Bearer $TOKEN"

  echo -e "${GREEN}✓ Keycloak prêt et token JWT obtenu${NC}"
  echo ""
}

start_services() {
  echo -e "${BLUE}[4/5] Démarrage des microservices...${NC}"

  local common_kc_env=""
  local test_mode_env=""

  if [[ "$MODE" == "auth" ]]; then
    common_kc_env="KEYCLOAK_URL=http://localhost:${KEYCLOAK_PORT} KEYCLOAK_REALM=FleetManagement KEYCLOAK_CLIENT_ID=Service-conducteurs"
  else
    test_mode_env="TEST_MODE=true"
  fi

  echo "  → Démarrage vehicule-service (port $VEHICULE_PORT)..."
  cd "$WORKSPACE/services/vehicule-service"
  eval "APP_PORT=$VEHICULE_PORT $test_mode_env $common_kc_env POSTGRES_HOST=localhost POSTGRES_PORT=55432 POSTGRES_DB=fleet POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres node src/app.js > /tmp/vehicule-service.log 2>&1 &"
  VEHICULE_PID=$!
  sleep 3

  echo "  → Démarrage maintenance-service (port $MAINTENANCE_PORT)..."
  cd "$WORKSPACE/services/maintenance-service"
  eval "APP_PORT=$MAINTENANCE_PORT $test_mode_env $common_kc_env node src/app.js > /tmp/maintenance-service.log 2>&1 &"
  MAINTENANCE_PID=$!
  sleep 3

  echo "  → Démarrage evenement-service (port $EVENEMENT_PORT)..."
  cd "$WORKSPACE/services/evenement-service"
  eval "APP_PORT=$EVENEMENT_PORT $test_mode_env $common_kc_env node src/app.js > /tmp/evenement-service.log 2>&1 &"
  EVENEMENT_PID=$!
  sleep 3

  echo "  → Démarrage conducteur-service (port $CONDUCTEUR_PORT)..."
  cd "$WORKSPACE/services/conducteur-service"
  eval "APP_PORT=$CONDUCTEUR_PORT $test_mode_env $common_kc_env POSTGRES_HOST=localhost POSTGRES_PORT=55432 POSTGRES_DB=fleet POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres node src/app.js > /tmp/conducteur-service.log 2>&1 &"
  CONDUCTEUR_PID=$!
  sleep 3

  echo -e "${GREEN}✓ Services démarrés${NC}"
  echo ""
}

check_health() {
  local port=$1
  local name=$2
  local max_attempts=15
  local attempt=0

  while [ "$attempt" -lt "$max_attempts" ]; do
    if curl -s "http://localhost:$port/" >/dev/null 2>&1; then
      echo -e "${GREEN}✓ $name est prêt${NC}"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  echo -e "${RED}✗ $name n'a pas répondu${NC}"
  return 1
}

wait_for_vehicle_status() {
  local vehicle_id=$1
  local expected_status=$2
  local timeout_seconds=${3:-30}
  local interval_seconds=2
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    local current_status
    current_status=$(curl -s -X GET "http://localhost:$VEHICULE_PORT/vehicles/$vehicle_id" "${auth_args[@]}" | jq -r '.statut // empty')

    if [[ "$current_status" == "$expected_status" ]]; then
      echo "$current_status"
      return 0
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  local final_status
  final_status=$(curl -s -X GET "http://localhost:$VEHICULE_PORT/vehicles/$vehicle_id" "${auth_args[@]}" | jq -r '.statut // empty')
  echo "$final_status"
  return 1
}

wait_for_active_assignments_count() {
  local driver_id=$1
  local expected_count=$2
  local timeout_seconds=${3:-30}
  local interval_seconds=2
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    local current_count
    current_count=$(curl -s -X GET "http://localhost:$CONDUCTEUR_PORT/drivers/$driver_id/assignments?active=true" "${auth_args[@]}" | jq 'length')

    if [[ "$current_count" == "$expected_count" ]]; then
      echo "$current_count"
      return 0
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  local final_count
  final_count=$(curl -s -X GET "http://localhost:$CONDUCTEUR_PORT/drivers/$driver_id/assignments?active=true" "${auth_args[@]}" | jq 'length')
  echo "$final_count"
  return 1
}

run_saga_tests() {
  echo -e "${BLUE}[5/5] Exécution des tests saga (${MODE})...${NC}"
  echo ""

  TEST_PASSED=0
  TEST_FAILED=0

  if [[ "$MODE" == "auth" ]]; then
    auth_args=(-H "$AUTH_HEADER")
  fi

  echo "▶ SCÉNARIO A1: Créer un conducteur"
  DRIVER_1_RESPONSE=$(curl -s -X POST "http://localhost:$CONDUCTEUR_PORT/drivers" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"keycloakId":"kc-e2e-driver-1","numeroPermis":"PERMIS-E2E-001","nom":"Dupont","prenom":"Jean","email":"jean.dupont.e2e@example.com","telephone":"+33170000001","statutPermis":true,"categoriePermis":"B"}')
  DRIVER_1_ID=$(echo "$DRIVER_1_RESPONSE" | jq -r '.id // empty')

  if [[ -n "$DRIVER_1_ID" ]]; then
    echo -e "${GREEN}✓ Conducteur créé: $DRIVER_1_ID${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création conducteur${NC}"
    echo "Response: $DRIVER_1_RESPONSE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO A2: Créer un véhicule AVAILABLE pour affectation"
  ASSIGN_VEHICLE_RESPONSE=$(curl -s -X POST "http://localhost:$VEHICULE_PORT/vehicles" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"marque":"Ford","modele":"Focus","immatriculation":"AS-100-AA","statut":"AVAILABLE"}')
  ASSIGN_VEHICLE_ID=$(echo "$ASSIGN_VEHICLE_RESPONSE" | jq -r '.id // empty')

  if [[ -n "$ASSIGN_VEHICLE_ID" ]]; then
    echo -e "${GREEN}✓ Véhicule affectable créé: $ASSIGN_VEHICLE_ID${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création véhicule affectable${NC}"
    echo "Response: $ASSIGN_VEHICLE_RESPONSE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO A3: Affectation acceptée (Saga A succès)"
  ASSIGNMENT_OK_RESPONSE=$(curl -s -X POST "http://localhost:$CONDUCTEUR_PORT/drivers/$DRIVER_1_ID/assignments" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"vehicleId\":\"$ASSIGN_VEHICLE_ID\",\"motif\":\"Mission quotidienne\"}")
  ASSIGNMENT_OK_ID=$(echo "$ASSIGNMENT_OK_RESPONSE" | jq -r '.id // empty')

  if [[ -n "$ASSIGNMENT_OK_ID" ]]; then
    echo -e "${GREEN}✓ Demande d'affectation créée: $ASSIGNMENT_OK_ID${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création affectation${NC}"
    echo "Response: $ASSIGNMENT_OK_RESPONSE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  ASSIGNED_VEHICLE_STATUS=$(wait_for_vehicle_status "$ASSIGN_VEHICLE_ID" "IN_USE" 30)
  if [[ "$ASSIGNED_VEHICLE_STATUS" == "IN_USE" ]]; then
    echo -e "${GREEN}✓ Véhicule affecté (IN_USE)${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Statut inattendu après affectation: $ASSIGNED_VEHICLE_STATUS (attendu IN_USE)${NC}"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO A4: Affectation refusée + compensation (Saga A échec)"
  DRIVER_2_RESPONSE=$(curl -s -X POST "http://localhost:$CONDUCTEUR_PORT/drivers" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"keycloakId":"kc-e2e-driver-2","numeroPermis":"PERMIS-E2E-002","nom":"Martin","prenom":"Lea","email":"lea.martin.e2e@example.com","telephone":"+33170000002","statutPermis":true,"categoriePermis":"B"}')
  DRIVER_2_ID=$(echo "$DRIVER_2_RESPONSE" | jq -r '.id // empty')

  REFUSED_VEHICLE_RESPONSE=$(curl -s -X POST "http://localhost:$VEHICULE_PORT/vehicles" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"marque":"Peugeot","modele":"308","immatriculation":"AS-101-BB","statut":"MAINTENANCE"}')
  REFUSED_VEHICLE_ID=$(echo "$REFUSED_VEHICLE_RESPONSE" | jq -r '.id // empty')

  ASSIGNMENT_KO_RESPONSE=$(curl -s -X POST "http://localhost:$CONDUCTEUR_PORT/drivers/$DRIVER_2_ID/assignments" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"vehicleId\":\"$REFUSED_VEHICLE_ID\",\"motif\":\"Mission refusée\"}")
  ASSIGNMENT_KO_ID=$(echo "$ASSIGNMENT_KO_RESPONSE" | jq -r '.id // empty')

  if [[ -n "$DRIVER_2_ID" && -n "$REFUSED_VEHICLE_ID" && -n "$ASSIGNMENT_KO_ID" ]]; then
    echo -e "${GREEN}✓ Préconditions scénario échec prêtes${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec préparation scénario échec d'affectation${NC}"
    echo "Driver response: $DRIVER_2_RESPONSE"
    echo "Vehicle response: $REFUSED_VEHICLE_RESPONSE"
    echo "Assignment response: $ASSIGNMENT_KO_RESPONSE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  ACTIVE_ASSIGNMENTS_COUNT=$(wait_for_active_assignments_count "$DRIVER_2_ID" 0 30)
  if [[ "$ACTIVE_ASSIGNMENTS_COUNT" == "0" ]]; then
    echo -e "${GREEN}✓ Compensation appliquée (assignation active annulée)${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Compensation non appliquée (assignations actives: $ACTIVE_ASSIGNMENTS_COUNT)${NC}"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO 1: Créer un véhicule"
  VEHICLE_RESPONSE=$(curl -s -X POST "http://localhost:$VEHICULE_PORT/vehicles" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"marque":"Toyota","modele":"Camry","immatriculation":"AB-123-CD","statut":"AVAILABLE"}')
  VEHICLE_ID=$(echo "$VEHICLE_RESPONSE" | jq -r '.id // empty')

  if [[ -n "$VEHICLE_ID" ]]; then
    echo -e "${GREEN}✓ Véhicule créé: $VEHICLE_ID${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création véhicule${NC}"
    echo "Response: $VEHICLE_RESPONSE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO 2: Maintenance HIGH (immobilisation immédiate)"
  MAINTENANCE_IMMEDIATE=$(curl -s -X POST "http://localhost:$MAINTENANCE_PORT/maintenances" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"vehicleId\":\"$VEHICLE_ID\",\"type\":\"ENGINE_CHECK\",\"reason\":\"Révision moteur critique\",\"urgencyLevel\":\"HIGH\",\"scheduledDate\":\"$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)\",\"requiresImmediateImmobilization\":false}")
  MAINTENANCE_ID=$(echo "$MAINTENANCE_IMMEDIATE" | jq -r '.id // empty')

  if [[ -n "$MAINTENANCE_ID" ]]; then
    echo -e "${GREEN}✓ Demande maintenance créée: $MAINTENANCE_ID${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création maintenance HIGH${NC}"
    echo "Response: $MAINTENANCE_IMMEDIATE"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  VEHICLE_STATUS=$(wait_for_vehicle_status "$VEHICLE_ID" "MAINTENANCE" 30)
  if [[ "$VEHICLE_STATUS" == "MAINTENANCE" ]]; then
    echo -e "${GREEN}✓ Véhicule immobilisé (MAINTENANCE)${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Statut inattendu: $VEHICLE_STATUS (attendu MAINTENANCE) après attente${NC}"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO 3: Créer un deuxième véhicule"
  VEHICLE_RESPONSE_2=$(curl -s -X POST "http://localhost:$VEHICULE_PORT/vehicles" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"marque":"Honda","modele":"Civic","immatriculation":"XY-456-ZZ","statut":"AVAILABLE"}')
  VEHICLE_ID_2=$(echo "$VEHICLE_RESPONSE_2" | jq -r '.id // empty')

  if [[ -n "$VEHICLE_ID_2" ]]; then
    echo -e "${GREEN}✓ Deuxième véhicule créé: $VEHICLE_ID_2${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création deuxième véhicule${NC}"
    echo "Response: $VEHICLE_RESPONSE_2"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  echo "▶ SCÉNARIO 4: Maintenance LOW (sans immobilisation immédiate)"
  MAINTENANCE_DELAYED=$(curl -s -X POST "http://localhost:$MAINTENANCE_PORT/maintenances" \
    "${auth_args[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"vehicleId\":\"$VEHICLE_ID_2\",\"type\":\"OIL_CHANGE\",\"reason\":\"Maintenance préventive\",\"urgencyLevel\":\"LOW\",\"scheduledDate\":\"$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)\",\"requiresImmediateImmobilization\":false}")
  MAINTENANCE_ID_2=$(echo "$MAINTENANCE_DELAYED" | jq -r '.id // empty')

  if [[ -n "$MAINTENANCE_ID_2" ]]; then
    echo -e "${GREEN}✓ Demande maintenance LOW créée: $MAINTENANCE_ID_2${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Échec création maintenance LOW${NC}"
    echo "Response: $MAINTENANCE_DELAYED"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  sleep 4

  VEHICLE_STATUS_2=$(curl -s -X GET "http://localhost:$VEHICULE_PORT/vehicles/$VEHICLE_ID_2" "${auth_args[@]}" | jq -r '.statut // empty')
  if [[ "$VEHICLE_STATUS_2" == "AVAILABLE" ]]; then
    echo -e "${GREEN}✓ Véhicule reste AVAILABLE${NC}"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗ Statut inattendu: $VEHICLE_STATUS_2 (attendu AVAILABLE)${NC}"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
  echo ""

  if [[ "$MODE" == "auth" ]]; then
    echo "▶ SCÉNARIO AUTH: Accès protégé sans token"
    NOAUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$VEHICULE_PORT/vehicles")
    if [[ "$NOAUTH_CODE" == "401" ]]; then
      echo -e "${GREEN}✓ Sans token => 401${NC}"
      TEST_PASSED=$((TEST_PASSED + 1))
    else
      echo -e "${RED}✗ Sans token attendu 401, obtenu $NOAUTH_CODE${NC}"
      TEST_FAILED=$((TEST_FAILED + 1))
    fi

    AUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH_HEADER" "http://localhost:$VEHICULE_PORT/vehicles")
    if [[ "$AUTH_CODE" == "200" ]]; then
      echo -e "${GREEN}✓ Avec token => 200${NC}"
      TEST_PASSED=$((TEST_PASSED + 1))
    else
      echo -e "${RED}✗ Avec token attendu 200, obtenu $AUTH_CODE${NC}"
      TEST_FAILED=$((TEST_FAILED + 1))
    fi
    echo ""
  fi
}

print_logs() {
  echo "=========================================="
  echo "📋 RÉSUMÉ DES LOGS DES SERVICES"
  echo "=========================================="
  echo ""

  if [ -f /tmp/maintenance-service.log ]; then
    echo -e "${YELLOW}[maintenance-service]${NC} (dernières 12 lignes)"
    tail -12 /tmp/maintenance-service.log
    echo ""
  fi

  if [ -f /tmp/vehicule-service.log ]; then
    echo -e "${YELLOW}[vehicule-service]${NC} (dernières 12 lignes)"
    tail -12 /tmp/vehicule-service.log
    echo ""
  fi

  if [ -f /tmp/evenement-service.log ]; then
    echo -e "${YELLOW}[evenement-service]${NC} (dernières 12 lignes)"
    tail -12 /tmp/evenement-service.log
    echo ""
  fi
}

print_results() {
  echo "=========================================="
  echo "📊 RÉSULTATS FINAUX"
  echo "=========================================="
  echo -e "Mode: ${BLUE}$MODE${NC}"
  echo -e "Tests réussis: ${GREEN}$TEST_PASSED${NC}"
  echo -e "Tests échoués: ${RED}$TEST_FAILED${NC}"
  echo ""

  if [ "$TEST_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ TOUS LES TESTS SONT PASSÉS${NC}"
    exit 0
  else
    echo -e "${RED}✗ Certains tests ont échoué${NC}"
    exit 1
  fi
}

if [[ "$MODE" != "test" && "$MODE" != "auth" ]]; then
  echo "Usage: $0 [test|auth]"
  exit 2
fi

echo "=========================================="
echo "🚀 TEST E2E SAGA MAINTENANCE"
echo "=========================================="
echo "Mode: $MODE"
echo ""

pkill -f 'services/.*/src/app.js' 2>/dev/null || true
docker rm -f e2e-postgres e2e-keycloak >/dev/null 2>&1 || true

start_kafka
start_postgres

if [[ "$MODE" == "auth" ]]; then
  setup_keycloak_auth_mode
else
  echo -e "${BLUE}[3/5] Mode test: bypass auth activé (TEST_MODE=true)${NC}"
  echo ""
fi

start_services

echo -e "${BLUE}[4.5/5] Vérification des services...${NC}"
check_health "$VEHICULE_PORT" 'vehicule-service'
check_health "$MAINTENANCE_PORT" 'maintenance-service'
check_health "$EVENEMENT_PORT" 'evenement-service'
check_health "$CONDUCTEUR_PORT" 'conducteur-service'
echo ""

run_saga_tests
print_logs
print_results
