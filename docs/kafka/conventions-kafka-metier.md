# Conventions Kafka — Topics métier

Ce document définit la convention officielle Kafka du projet.

## Convention de nommage

- **Topics métier** : noms de domaines métier au **pluriel**
- **Types d'événements** : `entite.action`

Exemples :

- Topic : `vehicules`
- Events : `vehicule.cree`, `vehicule.modifie`, `vehicule.supprime`

## Topics retenus

- `vehicules`
- `conducteurs`
- `maintenances`
- `localisations`
- `alertes`

## Schéma d'enveloppe événement

Chaque message Kafka doit contenir :

- `eventId` (UUID)
- `eventType` (ex: `vehicule.cree`)
- `entity` (ex: `vehicule`)
- `occurredAt` (ISO 8601)
- `payload` (données métier)

## Note de cohérence documentaire

Les documents PDF historiques peuvent contenir des conventions différentes (ex: topics en anglais `vehicle.updated`).
La source de vérité actuelle est ce fichier + la configuration active de l'infrastructure.