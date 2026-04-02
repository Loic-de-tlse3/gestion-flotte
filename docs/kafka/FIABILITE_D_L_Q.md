# Fiabilité Kafka (MVP) — Idempotence, retry, DLQ

## Objectif
Définir les garde-fous techniques pour éviter les incohérences en traitement asynchrone.

---

## 1) Idempotence consommateur (obligatoire)
Chaque consommateur doit pouvoir recevoir deux fois le même événement sans créer de doublon métier.

Stratégie MVP:
- Conserver les `eventId` déjà traités (table dédiée ou cache persistant).
- Si `eventId` déjà vu -> ignorer proprement et commit offset.

Exemples d’effets à éviter:
- Double immobilisation du même véhicule.
- Double assignation conducteur.

---

## 2) Retry (échecs temporaires)
En cas d’échec transitoire (DB indisponible, timeout réseau):
- N retries (ex: 3)
- Backoff exponentiel (ex: 1s, 2s, 4s)
- Puis envoi DLQ si échec persistant

Ne pas retry pour:
- JSON invalide
- Champ critique manquant
- `eventVersion` non supportée

---

## 3) DLQ (Dead Letter Queue)
Prévoir un topic DLQ par domaine ou global (`events.dlq`) selon votre convention.

Message DLQ recommandé:

```json
{
  "failedEvent": { "...": "..." },
  "failureReason": "VALIDATION_ERROR",
  "failedAt": "2026-04-01T10:00:00.000Z",
  "consumer": "conducteur-service",
  "retryCount": 3
}
```

Objectif:
- Ne jamais perdre silencieusement un événement.
- Permettre une reprise manuelle contrôlée.

---

## 4) Ordre et clés de partition
Pour garder l’ordre par saga métier:
- Utiliser une clé stable par saga:
  - Saga affectation: `assignmentId`
  - Saga maintenance: `maintenanceId`
  - Alternative commune: `correlationId`
- Tous les événements d’une même saga doivent partager cette clé.

---

## 5) Outbox pattern (prochaine itération)
Problème à éviter:
- DB commit OK mais publication Kafka échouée.

Approche cible:
- Écrire l’intention d’événement dans table `outbox` dans la même transaction DB.
- Un publisher asynchrone lit `outbox` et publie Kafka.
- Marquer `published_at` après succès.

Pour le MVP universitaire:
- Documenter la limite si l’outbox n’est pas encore implémentée.

---

## 6) Observabilité minimale
Logger pour chaque traitement:
- `eventId`
- `eventType`
- `correlationId`
- `service`
- `status` (SUCCESS/FAILED/RETRY/DLQ)

Ces champs permettent de reconstruire une saga de bout en bout.