# Contrats d’événements Kafka (MVP)

## Objectif
Définir un contrat d’échange stable, versionnable et testable pour les événements de Saga.

Références:
- `docs/kafka/conventions-kafka-metier.md`
- `docs/kafka/SAGA_MVP.md`
- `docs/kafka/Topics Kafka/Topics Kafka v2.pdf`

---

## Enveloppe standard (obligatoire)
Chaque événement doit respecter l’enveloppe suivante:

```json
{
  "eventId": "uuid",
  "eventType": "vehicule.modifie",
  "eventVersion": 1,
  "occurredAt": "2026-04-01T10:00:00.000Z",
  "entity": "vehicule",
  "correlationId": "uuid-saga",
  "causationId": "uuid-evenement-parent",
  "producer": "vehicule-service",
  "payload": {}
}
```

Règles:
- `eventId` unique globalement.
- `correlationId` constant pour toute la saga (affectation ou maintenance).
- `causationId` = `eventId` de l’événement qui a déclenché celui-ci.
- `eventVersion` commence à `1`.

---

## Contrats d’événements (payload)

## Mapping PDF (anglais) -> convention projet
- `vehicle.updated` -> `vehicule.modifie` (topic `vehicules`)
- `driver.updates` -> `conducteur.modifie` (topic `conducteurs`)
- `location.update` -> `localisation.mise_a_jour` (topic `localisations`)

## Saga A — Affectation (initiateur conducteur-service)

## `conducteur.affectation_demandee`
Producer: `conducteur-service`
Topic: `conducteurs`

Payload minimal:

```json
{
  "assignmentId": "uuid",
  "driverId": "uuid",
  "vehicleId": "uuid",
  "requestedAt": "2026-04-10T08:00:00.000Z"
}
```

## `vehicule.affectation_acceptee`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "assignmentId": "uuid",
  "vehicleId": "uuid"
}
```

## `vehicule.affectation_refusee`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "assignmentId": "uuid",
  "reasonCode": "VEHICLE_NOT_AVAILABLE",
  "reasonMessage": "Véhicule indisponible"
}
```

## `conducteur.assigne`
Producer: `conducteur-service`
Topic: `conducteurs`

```json
{
  "assignmentId": "uuid",
  "driverId": "uuid",
  "vehicleId": "uuid",
  "status": "ASSIGNED"
}
```

## `conducteur.affectation_annulee`
Producer: `conducteur-service`
Topic: `conducteurs`

```json
{
  "assignmentId": "uuid",
  "status": "CANCELLED",
  "reasonCode": "VEHICLE_NOT_AVAILABLE"
}
```

---

## Saga B — Maintenance (initiateur maintenance-service)

## `maintenance.demandee`
Producer: `maintenance-service`
Topic: `maintenances`

Payload minimal:

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid",
  "maintenanceType": "PREVENTIVE",
  "reason": "Révision annuelle des 50000 km",
  "scheduledDate": "2026-05-15T09:00:00.000Z",
  "urgencyLevel": "LOW",
  "requiresImmediateImmobilization": false,
  "requestedAt": "2026-04-10T08:00:00.000Z"
}
```

Champs:
- `maintenanceType`: `PREVENTIVE`, `CORRECTIVE`, `URGENT`
- `reason`: description libre de la maintenance
- `scheduledDate`: date/heure prévue pour démarrer la maintenance
- `urgencyLevel`: `LOW`, `MEDIUM`, `HIGH` (guide pour décision immobilisation)
- `requiresImmediateImmobilization`: hint du demandeur (peut être surchargé par logique métier)

## `vehicule.immobilise`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid",
  "immobilizationStartedAt": "2026-04-10T08:00:00.000Z"
}
```

**Décision**: Publiée quand `vehicule-service` décide que l'immobilisation est **immédiate et requise** (maintenance urgente ou pas de date lointaine).

## `vehicule.maintenance_planifiee_sans_immobilisation`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid",
  "scheduledDate": "2026-05-15T09:00:00.000Z",
  "reason": "Maintenance bénigne/préventive planifiée à distance"
}
```

**Décision**: Publiée quand `vehicule-service` décide que l'immobilisation n'est **pas immédiate** (maintenance préventive, date lointaine, priorité basse).

---

## `vehicule.immobilisation_echouee`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "maintenanceId": "uuid",
  "reasonCode": "VEHICLE_NOT_FOUND_OR_BUSY",
  "reasonMessage": "Véhicule introuvable ou déjà indisponible"
}
```

## `conducteur.desassigne`
Producer: `conducteur-service`
Topic: `conducteurs`

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid",
  "driverId": "uuid"
}
```

## `conducteur.desassignation_echouee`
Producer: `conducteur-service`
Topic: `conducteurs`

```json
{
  "maintenanceId": "uuid",
  "reasonCode": "DESASSIGNATION_ECHOUEE",
  "reasonMessage": "Impossible de désassigner le conducteur"
}
```

## `maintenance.planifiee`
Producer: `maintenance-service`
Topic: `maintenances`

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid",
  "status": "SCHEDULED"
}
```

## `maintenance.annulee`
Producer: `maintenance-service`
Topic: `maintenances`

```json
{
  "maintenanceId": "uuid",
  "status": "CANCELLED",
  "reasonCode": "DESASSIGNATION_ECHOUEE"
}
```

## `vehicule.libere`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "maintenanceId": "uuid",
  "vehicleId": "uuid"
}
```

## `alerte.creee`
Producer: `evenement-service`
Topic: `alertes`

```json
{
  "sagaId": "uuid",
  "severity": "HIGH",
  "message": "Saga annulée suite à un échec métier"
}
```

## `vehicule.modifie`
Producer: `vehicule-service`
Topic: `vehicules`

```json
{
  "vehicleId": "uuid",
  "changes": {
    "statut": "IN_USE"
  }
}
```

## `conducteur.modifie`
Producer: `conducteur-service`
Topic: `conducteurs`

```json
{
  "driverId": "uuid",
  "changes": {
    "disponibilite": false
  }
}
```

## `localisation.mise_a_jour`
Producer: `localisation-service`
Topic: `localisations`

```json
{
  "vehicleId": "uuid",
  "latitude": 48.8566,
  "longitude": 2.3522,
  "capturedAt": "2026-04-10T08:00:00.000Z"
}
```

---

## Compatibilité et versioning
- Ajouter de nouveaux champs: autorisé (backward compatible).
- Renommer/supprimer un champ: interdit sans incrément majeur de version.
- Toute évolution non compatible doit créer un nouvel `eventVersion` et être documentée.

---

## Validation (recommandée)
- Vérifier structure minimale à la consommation (présence des champs clés).
- Rejeter vers DLQ si JSON invalide ou champs critiques manquants.
- Logger `eventId` + `correlationId` pour chaque traitement.