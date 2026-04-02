# Saga inter-services (MVP) — Gestion de flotte

## Objectif
Décrire un flux Saga minimal entre microservices via Kafka, sans transaction distribuée, avec gestion explicite des échecs par compensation.

Ce document complète:
- `docs/kafka/conventions-kafka-metier.md`
- `docs/kafka/Topics Kafka/Topics Kafka v2.pdf` (source de vérité des topics)

---

## Cas métier choisi (MVP)
Deux sagas métier complémentaires:

1. **Saga A — Affectation opérationnelle**
  - Initiateur: `conducteur-service`
  - But: associer un conducteur à un véhicule disponible.

2. **Saga B — Maintenance véhicule**
  - Initiateur: `maintenance-service`
  - But: immobiliser un véhicule pour réparation et gérer les compensations si besoin.

Services impliqués:
- `conducteur-service`
- `maintenance-service`
- `vehicule-service`
- `evenement-service` (journalisation/alerte)

Objectif final:
- Affectation validée si véhicule + conducteur sont cohérents.
- Maintenance planifiée si immobilisation réussie.

---

## Modèle de Saga retenu
Approche **choreography** (sans orchestrateur central dédié).

Principe:
1. Le service propriétaire du cas d’usage publie l’événement initial.
2. Les services aval réagissent en consommant/publiant leurs propres événements.
3. En cas d’échec, un événement d’annulation déclenche les compensations.

---

## États métier (MVP)
### Affectation
- `PENDING`
- `ASSIGNED`
- `CANCELLED`

### Maintenance
- `PENDING`
- `SCHEDULED`
- `CANCELLED`

---

## Saga A — Affectation (initiateur: conducteur-service)

## Flux nominal (succès)
1. API d’affectation reçue par `conducteur-service`
2. `conducteur-service` crée intention d’affectation `PENDING`
3. Publication: `conducteur.affectation_demandee` (topic `conducteurs`)
4. `vehicule-service` vérifie disponibilité et réserve l’état d’affectation
5. Publication: `vehicule.affectation_acceptee` (topic `vehicules`)
6. `conducteur-service` confirme l’affectation
7. Publication finale: `conducteur.assigne` (topic `conducteurs`)
8. Publication de cohérence flotte: `vehicule.modifie` (topic `vehicules`)

## Flux d’échec + compensation
Exemple: véhicule indisponible.

1. `conducteur.affectation_demandee`
2. `vehicule.affectation_refusee`
3. `conducteur-service` passe en `CANCELLED`
4. Publication: `conducteur.affectation_annulee` (topic `conducteurs`)
5. `evenement-service` publie `alerte.creee` (topic `alertes`)

Règles de décision:
- `ASSIGNED` uniquement après `vehicule.affectation_acceptee`.
- `CANCELLED` dès événement bloquant (`vehicule.affectation_refusee`, erreur métier conducteur).

---

## Saga B — Maintenance (initiateur: maintenance-service)

### Flux nominal — Cas 1 (immobilisation immédiate requise)
Maintenance urgente ou imminente (ex: moteur endommagé, maintenance prévue dans 2 jours).

1. API `POST /maintenances` -> `maintenance-service` (raison + date prévue)
2. `maintenance-service` crée demande `PENDING`
3. Publication: `maintenance.demandee` (topic `maintenances`, avec raison + scheduledDate + urgencyLevel)
4. `vehicule-service` décide: la date est proche **OU** urgencyLevel = HIGH → immobilisation immédiate
5. Publication: `vehicule.immobilise` (topic `vehicules`)
6. `maintenance-service` passe la demande en `SCHEDULED`
7. Publication finale: `maintenance.planifiee` (topic `maintenances`)

### Flux nominal — Cas 2 (immobilisation retardée)
Maintenance préventive bénigne (ex: révision 50k km, prévue dans 2 mois).

1. API `POST /maintenances` -> `maintenance-service` (raison + date lointaine prévue)
2. `maintenance-service` crée demande `PENDING`
3. Publication: `maintenance.demandee` (topic `maintenances`, avec raison + scheduledDate + urgencyLevel=LOW)
4. `vehicule-service` décide: la date est lointaine **ET** urgencyLevel = LOW → pas d'immobilisation immédiate
5. Publication: `vehicule.maintenance_planifiee_sans_immobilisation` (topic `vehicules`, avec scheduledDate)
6. `maintenance-service` passe la demande en `SCHEDULED`
7. Publication finale: `maintenance.planifiee` (topic `maintenances`)

**Note**: L'immobilisation réelle sera déclenchée plus tard:
- Soit par API: `PUT /maintenances/{id}/immobilise` (appelée quand la date approche)
- Soit par orchestration métier: scheduler notifiant `vehicule-service` quand immobilisation urgente

---

### Flux d'échec + compensation (applicable aux deux cas)
Exemple: véhicule introuvable/occupé/indisponible.

**Cas 1 (immobilisation immédiate):**
1. `maintenance.demandee`
2. `vehicule.immobilisation_echouee` (ex: véhicule affecté à un conducteur)
3. `maintenance-service` passe en `CANCELLED` + publie `maintenance.annulee`
4. `evenement-service` publie `alerte.creee`

**Cas 2 (immobilisation retardée):**
1. `maintenance.demandee`
2. `vehicule.maintenance_planifiee_sans_immobilisation` (succès, reste à l'état normal)
3. Plus tard, quand immobilisation est requise (date approche ou changement d'urgence):
   - Appel API ou événement: `maintenance-service` demande immobilisation tardive
   - Si immobilisation échoue: `vehicule.immobilisation_echouee` → `maintenance.annulee` + `alerte.creee`

Cas particulier recommandé:
- Si une maintenance (urgente) est demandée sur un véhicule déjà affecté, déclencher une sous-étape de désassignation via `conducteur-service`.
- En cas d’échec de désassignation: `maintenance.annulee` + `vehicule.libere`.

Note:
- Aucune suppression physique obligatoire en MVP.
- Préférer un statut métier (`CANCELLED`) pour audit et observabilité.

---

## Règles de décision (maintenance)
- Une maintenance peut être `SCHEDULED` après:
  - `vehicule.immobilise` (cas 1, immobilisation immédiate)
  - `vehicule.maintenance_planifiee_sans_immobilisation` (cas 2, immobilisation retardée)
- Une maintenance doit être `CANCELLED` dès échec bloquant:
  - `vehicule.immobilisation_echouee` (si immobilisation requise mais échoue)
  - `conducteur.desassignation_echouee` (si la sous-étape existe)
- **Logique de décision d'immobilisation** (à `vehicule-service`):
  - Si `urgencyLevel = HIGH` → immobilisation immédiate
  - Si `scheduledDate` < now + 24h → immobilisation immédiate
  - Sinon → immobilisation retardée (via cas 2)

---

## Événements minimum à implémenter
### Saga A — Affectation
- `conducteur.affectation_demandee`
- `vehicule.affectation_acceptee`
- `vehicule.affectation_refusee`
- `conducteur.assigne`
- `conducteur.affectation_annulee`
- `vehicule.modifie`

### Saga B — Maintenance
- `maintenance.demandee`
- `vehicule.immobilise` (cas 1: immobilisation immédiate)
- `vehicule.maintenance_planifiee_sans_immobilisation` (cas 2: immobilisation retardée)
- `vehicule.immobilisation_echouee`
- `maintenance.planifiee`
- `maintenance.annulee`
- `vehicule.libere` (si immobilisation active et annulation)
- `alerte.creee`

## Couverture des 5 topics
- `vehicules` -> `vehicule.affectation_acceptee`, `vehicule.affectation_refusee`, `vehicule.modifie`, `vehicule.immobilise`, `vehicule.maintenance_planifiee_sans_immobilisation`, `vehicule.immobilisation_echouee`, `vehicule.libere`
- `conducteurs` -> `conducteur.affectation_demandee`, `conducteur.assigne`, `conducteur.affectation_annulee`
- `maintenances` -> `maintenance.demandee`, `maintenance.planifiee`, `maintenance.annulee`
- `localisations` -> `localisation.mise_a_jour`
- `alertes` -> `alerte.creee`

Nommage appliqué: `entite.action` (conforme à `conventions-kafka-metier.md`).

---

## Critères d’acceptation (avant implémentation complète)
- La saga d’affectation est initiée par `conducteur-service`.
- La saga de maintenance est initiée par `maintenance-service`.
- Chaque saga a un flux succès et un flux échec testables.
- Les services restent cohérents après retries (pas de double attribution).