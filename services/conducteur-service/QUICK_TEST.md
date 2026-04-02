# Conducteur Service - Test rapide

Guide minimal pour tester le service sans complexité.

## Où lancer les commandes
- `kubectl ...` et migration SQL : **à la racine du projet** (`gestion-de-flotte-automobile-main`)
- `npm run start` : **dans** `services/conducteur-service`
- `curl` : n'importe où

---

## 1) Ouvrir le tunnel PostgreSQL

```bash
kubectl port-forward -n flotte-infrastructure svc/postgresql 5432:5432
```

Laisse ce terminal ouvert.

---

## 2) Initialiser la base (une seule fois)

```bash
kubectl exec -i -n flotte-infrastructure postgresql-0 -- \
	env PGPASSWORD='archi_distribuée' \
	psql -h 127.0.0.1 -U utilisateur_flotte -d flotte_db -f - \
	< docs/bdd/fleet-microservices-sql/V001_initial_setup.sql
```

Notes:
- Si tu vois `already exists`, ce n'est pas bloquant (base déjà initialisée).
- Cette étape est à refaire seulement si tu recrées/reset la base.
- Si ta base existe déjà, applique aussi l'unicité téléphone: `kubectl exec -i -n flotte-infrastructure postgresql-0 -- env PGPASSWORD='archi_distribuée' psql -h 127.0.0.1 -U utilisateur_flotte -d flotte_db -f - < docs/bdd/fleet-microservices-sql/V007_add_unique_phone_constraint.sql`

---

## 3) Lancer le service conducteur

```bash
cd services/conducteur-service
APP_PORT=3001 DATABASE_URL='postgresql://utilisateur_flotte:<MDP DE VOTRE BD>@localhost:5432/flotte_db' npm run start
```

Laisse ce terminal ouvert.

---

## 4) Créer un conducteur

```bash
TS=$(date +%s%N)
TEL="06${TS: -8}"
DRIVER_ID=$(curl -s -X POST http://localhost:3001/drivers \
	-H "Content-Type: application/json" \
	-d '{"keycloakId":"kc-test-'$(date +%s%N)'","numeroPermis":"75PC'$(date +%s%N | tail -c 7)'","nom":"Dupont","prenom":"Jean","email":"jean.dupont@test.fr","telephone":"'$TEL'","statutPermis":true,"categoriePermis":"B"}' \
	| jq -r '.id')
echo "$DRIVER_ID"
```

Tu dois obtenir un UUID (pas `null`).

---

## 5) Créer puis fermer une assignation

```bash
VEHICLE_ID="550e8400-e29b-41d4-a716-446655440001"
ASSIGNMENT_ID=$(curl -s -X POST http://localhost:3001/drivers/$DRIVER_ID/assignments \
	-H "Content-Type: application/json" \
	-d '{"vehicleId":"'$VEHICLE_ID'","dateDebut":"2026-03-29T10:00:00Z","dateFin":"2026-03-30T18:00:00Z","motif":"Livraison client"}' \
	| jq -r '.id')
echo "$ASSIGNMENT_ID"
curl -s -X PUT http://localhost:3001/assignments/$ASSIGNMENT_ID/end \
	-H "Content-Type: application/json" \
	-d '{"dateFin":"2026-03-30T17:35:00Z"}' \
	| jq '.'
```

---

## 6) Vérifier qu'il n'y a plus d'assignation active

```bash
	curl -s "http://localhost:3001/drivers/$DRIVER_ID/assignments?active=true" | jq 'length'
```

Résultat attendu: `0`
