# Runbook — Test et exploitation Saga Kafka (MVP)

## Objectif
Procédure courte pour valider le flux Saga et diagnostiquer les incidents en local.

---

## 1) Préparation
- Démarrer Kafka/Zookeeper (ou cluster équivalent projet).
- Démarrer les services impliqués (`maintenance`, `vehicule`, `conducteur`, `evenement`).
- Vérifier que la configuration des topics suit `Topics Kafka v2.pdf`.

Checklist:
- [ ] Broker Kafka joignable
- [ ] Services démarrés sans erreur
- [ ] Topics présents

---

## 2) Scénario A — Affectation (succès)
1. Déclencher une affectation via API `conducteur-service`.
2. Vérifier publication `conducteur.affectation_demandee` (topic `conducteurs`).
3. Vérifier réception et publication `vehicule.affectation_acceptee` (topic `vehicules`).
4. Vérifier publication finale `conducteur.assigne` (topic `conducteurs`).
5. Vérifier `vehicule.modifie` et `localisation.mise_a_jour` si applicables.

Résultat attendu:
- Affectation en `ASSIGNED`.
- Pas d’événement en DLQ.

---

## 3) Scénario A — Affectation (échec)
1. Simuler un véhicule indisponible.
2. Déclencher une affectation.
3. Vérifier `vehicule.affectation_refusee`.
4. Vérifier `conducteur.affectation_annulee`.
5. Vérifier `alerte.creee`.

Résultat attendu:
- Affectation en `CANCELLED`.
- Aucune affectation active résiduelle.

---

## 4) Scénario B — Maintenance (succès, immobilisation immédiate)
Maintenance urgente (ex: moteur endommagé ou date imminente).

1. Déclencher une demande de maintenance via API `maintenance-service` avec:
   - `urgencyLevel: HIGH` OU
   - `scheduledDate` < now + 24h
2. Vérifier publication `maintenance.demandee` (topic `maintenances`).
3. Vérifier réception et publication `vehicule.immobilise` (topic `vehicules`).
4. Vérifier publication finale `maintenance.planifiee` (topic `maintenances`).

Résultat attendu:
- Maintenance en `SCHEDULED`.
- Véhicule immobilisé immédiatement.
- Pas d'événement en DLQ.

---

## 4b) Scénario B — Maintenance (succès, immobilisation retardée)
Maintenance préventive bénigne (ex: révision 50k km, prévue dans 2 mois).

1. Déclencher une demande de maintenance via API `maintenance-service` avec:
   - `urgencyLevel: LOW` ET
   - `scheduledDate` >= now + 7 jours
2. Vérifier publication `maintenance.demandee` (topic `maintenances`).
3. Vérifier réception et publication `vehicule.maintenance_planifiee_sans_immobilisation` (topic `vehicules`).
4. Vérifier publication finale `maintenance.planifiee` (topic `maintenances`).
5. Vérifier que le véhicule **reste disponible** pour affectations.

Résultat attendu:
- Maintenance en `SCHEDULED` (étape 1).
- **Véhicule NON immobilisé**, reste opérationnel.
- Pas d’événement en DLQ.

---

## 6) Scénario B — Maintenance (échec + compensation)
Immobilisation échouée (véhicule indisponible) ou désassignation impossible.

**Cas 1 (immobilisation immédiate requise):**

---

## 7) Scénario B — Maintenance (échec + compensation)
Immobilisation échouée (véhicule indisponible) ou désassignation impossible.

**Cas 1 (immobilisation immédiate requise):**
1. Simuler un véhicule indisponible/occupé.
2. Déclencher une maintenance urgente.
3. Vérifier `vehicule.immobilisation_echouee`.
4. Vérifier `maintenance.annulee`.
5. Vérifier `alerte.creee`.

Résultat attendu:
- Maintenance en `CANCELLED`.
- État véhicule cohérent.

**Cas 2 (immobilisation retardée):**
La saga réussit à étape 1 (planification), mais l'immobilisation tardive échoue quand retardée.
1. Maintenance initialement planifiée sans immobilisation immédiate.
2. Plus tard, quand date se rapproche, API demande immobilisation tardive.
3. Vérifier `vehicule.immobilisation_echouee` si véhicule indisponible.
4. Vérifier `maintenance.annulee` + `alerte.creee`.
- Le même `correlationId` est visible sur tous les événements de la saga.
- Un redelivery du même `eventId` ne produit pas de doublon (idempotence).
- Les erreurs non récupérables arrivent en DLQ.

---

## 8) Procédure incident (diagnostic rapide)
Quand une saga reste bloquée:
1. Rechercher `correlationId` dans les logs des services.
2. Identifier le dernier événement émis avec succès.
3. Vérifier si l’événement suivant est en DLQ.
4. Vérifier la cause (`failureReason`).
5. Corriger la cause puis rejouer l’événement si nécessaire.

---

## 9) Politique de rejeu (MVP)
- Rejeu uniquement après correction de la cause.
- Rejeu contrôlé par un script/outillage manuel.
- Toujours conserver la trace du rejeu (`replayedBy`, `replayedAt`).

---

## 10) Critères de validation avant soutenance
- [ ] Saga A (affectation) succès démontrée
- [ ] Saga A (affectation) échec démontré
- [ ] Saga B (maintenance, cas 1) succès & immobilisation immédiate
- [ ] Saga B (maintenance, cas 2) succès & véhicule NON immobilisé
- [ ] Saga B (maintenance) échec + compensation démontré
- [ ] Corrélation observée via `correlationId`
- [ ] Aucun doublon métier lors d’un redelivery
- [ ] DLQ exploitée sur erreur non récupérable