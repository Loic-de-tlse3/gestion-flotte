# Rapport de tests des évènements Kafka

_Date : 2 avril 2026_

## 1) Objectif
Valider le bon fonctionnement de la chaîne évènementielle Kafka pour les sagas maintenance et assignation, puis documenter le diagnostic et les corrections effectuées.

## 2) Périmètre couvert
- Publication de `conducteur.affectation_demandee` par le `conducteur-service`
- Consommation de `conducteur.affectation_demandee` par le `vehicule-service`
- Publication de `vehicule.affectation_acceptee` / `vehicule.affectation_refusee`
- Compensation `conducteur.affectation_annulee` en cas de refus
- Publication de `maintenance.demandee` par le `maintenance-service`
- Consommation de `maintenance.demandee` par le `vehicule-service`
- Application des règles d’immobilisation côté véhicule
- Publication des évènements retour côté véhicule (`vehicule.immobilise`, etc.)
- Vérification de bout en bout via le script E2E

## 3) Constat initial
Lors d’un premier passage E2E, un échec apparaissait sur le scénario :
- **Maintenance HIGH (immobilisation immédiate)**
- Statut observé trop tôt : `AVAILABLE` au lieu de `MAINTENANCE`

Ce comportement était intermittent et lié au timing de propagation asynchrone (Kafka + traitement consommateur), pas à une régression métier.

## 4) Diagnostic réalisé
### 4.1 Vérifications de code
- Consumer véhicule sur topic `maintenances` :
  - `services/vehicule-service/src/kafka/maintenanceEventsConsumer.js`
- Publication `maintenance.demandee` :
  - `services/maintenance-service/src/services/maintenanceService.js`
- Règle d’immobilisation immédiate (HIGH / urgence) :
  - `services/vehicule-service/src/services/vehicleService.js`

### 4.2 Vérifications d’exécution
- Reproduction ciblée avec services lancés localement
- Contrôle des logs applicatifs
- Vérification différée du statut : après délai supplémentaire, le statut passe bien à `MAINTENANCE`

**Conclusion diagnostic :**
Le flux Kafka fonctionne. Le faux négatif venait d’une assertion E2E trop précoce.

## 5) Correction apportée
### Fichier modifié
- `e2e-saga-test.sh`

### Changement
- Remplacement de l’attente fixe (`sleep 4`) du scénario HIGH
- Ajout d’une attente active (polling) via `wait_for_vehicle_status(...)` :
  - vérification périodique du statut jusqu’à `MAINTENANCE`
  - timeout contrôlé (30s)

### Bénéfice
- Réduction des faux échecs liés aux délais asynchrones
- Validation E2E plus robuste sans modifier la logique métier

## 6) Résultats de validation après correction
### Exécution complète mode `test`
- **Tests réussis : 12**
- **Tests échoués : 0**
- Verdict : ✅ tous les scénarios passent

### Exécution complète mode `auth`
- **Tests réussis : 14**
- **Tests échoués : 0**
- Vérifications auth incluses : accès protégé sans token (401) et avec token (200)
- Verdict : ✅ tous les scénarios passent

## 7) Saga A — Assignation implémentée
### Services et composants ajoutés/étendus
- `services/conducteur-service/src/services/conducteurService.js`
  - publication `conducteur.affectation_demandee`
  - traitement des retours `vehicule.affectation_acceptee` / `vehicule.affectation_refusee`
  - publication `conducteur.assigne` / `conducteur.affectation_annulee`
- `services/conducteur-service/src/kafka/vehicleAssignmentEventsConsumer.js`
  - nouveau consumer du topic `vehicules`
- `services/vehicule-service/src/services/vehicleService.js`
  - nouveau handler `handleAssignmentDemand`
- `services/vehicule-service/src/kafka/conducteurEventsConsumer.js`
  - nouveau consumer du topic `conducteurs`

### Comportement validé
- **Flux succès** : véhicule `AVAILABLE` -> `IN_USE` + événement `vehicule.affectation_acceptee`
- **Flux échec** : véhicule indisponible -> `vehicule.affectation_refusee` + compensation conducteur (`conducteur.affectation_annulee`)

## 8) Évènements Kafka validés
- `conducteur.affectation_demandee`
- `vehicule.affectation_acceptee`
- `vehicule.affectation_refusee`
- `conducteur.assigne`
- `conducteur.affectation_annulee`
- `maintenance.demandee`
- `vehicule.immobilise`
- `vehicule.maintenance_planifiee_sans_immobilisation`
- `vehicule.immobilisation_echouee` (couvert par le flux et la logique, même si non déclenché dans les scénarios passants ci-dessus)

## 9) Conclusion
Le fonctionnement Kafka attendu est validé de bout en bout pour les deux sagas.
Les changements couvrent à la fois la fiabilité du test E2E (timing maintenance) et l’implémentation effective de la saga d’assignation.
