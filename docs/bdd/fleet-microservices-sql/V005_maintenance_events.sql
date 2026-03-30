-- =============================================================================
-- Fleet Management Microservices - Migration V005
-- Mise à jour Maintenance + Nouveau Service Événements
-- =============================================================================
-- Ce script complète le service Maintenance et crée le service Événements
-- Compatible avec PostgreSQL 14+
-- =============================================================================

-- =============================================================================
-- PARTIE 1 : MISE À JOUR DU SERVICE MAINTENANCE
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Ajout des colonnes type_maintenance et cout_estime
-- -----------------------------------------------------------------------------

-- Créer le type ENUM pour le type de maintenance (si pas déjà existant)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maintenance_type_enum') THEN
        CREATE TYPE maintenance_type_enum AS ENUM (
            'PREVENTIVE',
            'CURATIVE'
        );
    END IF;
END $$;

-- Ajouter la colonne type_maintenance si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_maintenance' 
        AND table_name = 'maintenance_records' 
        AND column_name = 'type_maintenance'
    ) THEN
        ALTER TABLE service_maintenance.maintenance_records
        ADD COLUMN type_maintenance maintenance_type_enum NOT NULL DEFAULT 'PREVENTIVE';
    END IF;
END $$;

-- Ajouter la colonne cout_estime si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_maintenance' 
        AND table_name = 'maintenance_records' 
        AND column_name = 'cout_estime'
    ) THEN
        ALTER TABLE service_maintenance.maintenance_records
        ADD COLUMN cout_estime DECIMAL(10, 2);
    END IF;
END $$;

-- Ajouter un index sur type_maintenance pour les filtres
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_maintenance' 
        AND tablename = 'maintenance_records' 
        AND indexname = 'idx_maintenance_type'
    ) THEN
        CREATE INDEX idx_maintenance_type 
            ON service_maintenance.maintenance_records(type_maintenance);
    END IF;
END $$;


-- =============================================================================
-- PARTIE 2 : CRÉATION DU SERVICE ÉVÉNEMENTS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schéma service_evenements
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS service_evenements;


-- -----------------------------------------------------------------------------
-- Table alerts (alertes véhicule)
-- -----------------------------------------------------------------------------

-- Créer le type ENUM pour le type d'alerte
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type_enum') THEN
        CREATE TYPE alert_type_enum AS ENUM (
            'SPEEDING',
            'GEO_FENCE_BREACH',
            'MAINTENANCE_DUE',
            'FUEL_LOW',
            'BATTERY_LOW',
            'COLLISION',
            'UNAUTHORIZED_USE'
        );
    END IF;
END $$;

-- Créer le type ENUM pour le niveau de sévérité
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'severity_level_enum') THEN
        CREATE TYPE severity_level_enum AS ENUM (
            'LOW',
            'MEDIUM',
            'HIGH',
            'CRITICAL'
        );
    END IF;
END $$;

-- Créer le type ENUM pour le statut d'alerte
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_status_enum') THEN
        CREATE TYPE alert_status_enum AS ENUM (
            'ACTIVE',
            'ACKNOWLEDGED',
            'RESOLVED',
            'DISMISSED'
        );
    END IF;
END $$;

-- Créer la table alerts
CREATE TABLE IF NOT EXISTS service_evenements.alerts (
    -- Primary Key: UUID
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Référence véhicule (UUID)
    vehicle_id UUID NOT NULL,
    
    -- Type d'alerte (ENUM)
    type_alerte alert_type_enum NOT NULL,
    
    -- Description de l'alerte
    description TEXT,
    
    -- Niveau de sévérité (ENUM)
    niveau_severity severity_level_enum NOT NULL DEFAULT 'MEDIUM',
    
    -- Statut de l'alerte (ENUM)
    statut alert_status_enum NOT NULL DEFAULT 'ACTIVE',
    
    -- Horodatage de l'alerte
    date_alerte TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Horodatage de résolution (si applicable)
    date_résolution TIMESTAMPTZ,
    
    -- Audit columns
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index pour les alertes
CREATE INDEX IF NOT EXISTS idx_alerts_vehicle_id 
    ON service_evenements.alerts(vehicle_id);

CREATE INDEX IF NOT EXISTS idx_alerts_type 
    ON service_evenements.alerts(type_alerte);

CREATE INDEX IF NOT EXISTS idx_alerts_status 
    ON service_evenements.alerts(statut);

CREATE INDEX IF NOT EXISTS idx_alerts_severity 
    ON service_evenements.alerts(niveau_severity);

CREATE INDEX IF NOT EXISTS idx_alerts_date 
    ON service_evenements.alerts(date_alerte DESC);

-- Trigger pour updated_at
CREATE OR REPLACE FUNCTION service_evenements.update_alerts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_alerts_updated_at 
    BEFORE UPDATE ON service_evenements.alerts
    FOR EACH ROW 
    EXECUTE FUNCTION service_evenements.update_alerts_updated_at();


-- -----------------------------------------------------------------------------
-- Table notifications_log (journal des notifications)
-- -----------------------------------------------------------------------------

-- Créer le type ENUM pour le canal de notification
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_channel_enum') THEN
        CREATE TYPE notification_channel_enum AS ENUM (
            'EMAIL',
            'SMS',
            'PUSH',
            'WEBHOOK',
            'IN_APP'
        );
    END IF;
END $$;

-- Créer la table notifications_log
CREATE TABLE IF NOT EXISTS service_evenements.notifications_log (
    -- Primary Key: UUID
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Clé étrangère vers alerts
    alert_id UUID NOT NULL,
    
    -- Destinataire de la notification
    destinataire VARCHAR(255) NOT NULL,
    
    -- Canal utilisé (ENUM)
    canal notification_channel_enum NOT NULL,
    
    -- Contenu du message
    message TEXT,
    
    -- Statut de la notification
    statut_envoi VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    
    -- Horodatage de l'envoi
    horodatage TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Réponse du canal (optionnel)
    réponse TEXT,
    
    -- Audit columns
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Contrainte de clé étrangère
    CONSTRAINT fk_notifications_alert 
        FOREIGN KEY (alert_id) 
        REFERENCES service_evenements.alerts(id)
        ON DELETE CASCADE
);

-- Index pour les notifications
CREATE INDEX IF NOT EXISTS idx_notifications_alert_id 
    ON service_evenements.notifications_log(alert_id);

CREATE INDEX IF NOT EXISTS idx_notifications_destinataire 
    ON service_evenements.notifications_log(destinataire);

CREATE INDEX IF NOT EXISTS idx_notifications_canal 
    ON service_evenements.notifications_log(canal);

CREATE INDEX IF NOT EXISTS idx_notifications_horodatage 
    ON service_evenements.notifications_log(horodatage DESC);

-- Trigger pour updated_at
CREATE OR REPLACE FUNCTION service_evenements.update_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_notifications_updated_at 
    BEFORE UPDATE ON service_evenements.notifications_log
    FOR EACH ROW 
    EXECUTE FUNCTION service_evenements.update_notifications_updated_at();


-- =============================================================================
-- PARTIE 3 : SÉCURITÉ & PERMISSIONS
-- -----------------------------------------------------------------------------

-- Créer le rôle pour le service événements
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_service_evenements') THEN
        CREATE ROLE role_service_evenements WITH LOGIN PASSWORD 'evenements_secure_password';
    END IF;
END $$;

-- Accorder les permissions
GRANT USAGE ON SCHEMA service_evenements TO role_service_evenements;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA service_evenements TO role_service_evenements;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service_evenements TO role_service_evenements;

-- Permissions par défaut pour les nouveaux objets
ALTER DEFAULT PRIVILEGES IN SCHEMA service_evenements 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_service_evenements;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_evenements 
    GRANT USAGE, SELECT ON SEQUENCES TO role_service_evenements;


-- =============================================================================
-- PARTIE 4 : DONNÉES DE TEST
-- -----------------------------------------------------------------------------

-- Insérer des données de test pour la maintenance (type PREVENTIVE)
INSERT INTO service_maintenance.maintenance_records 
    (id, vehicle_id, type_maintenance, description, coût, cout_estime, date_début, date_fin, statut, created_at, updated_at)
VALUES 
    ('a1bbcc99-9c0b-4ef8-bb6d-6bb9bd380a01', 
     'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     'PREVENTIVE', 
     'Révision annuelle - Contrôle général et vidange',
     250.00,
     300.00,
     CURRENT_TIMESTAMP + INTERVAL '5 days', 
     NULL, 
     'PLANIFIÉ',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- Insérer des données de test pour les alertes (type SPEEDING)
INSERT INTO service_evenements.alerts 
    (id, vehicle_id, type_alerte, description, niveau_severity, statut, date_alerte, created_at, updated_at)
VALUES 
    ('b2ccdd99-9c0b-4ef8-bb6d-6bb9bd380a02', 
     'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     'SPEEDING', 
     'Excès de vitesse détecté: 85 km/h dans une zone limitée à 50 km/h',
     'HIGH', 
     'ACTIVE', 
     CURRENT_TIMESTAMP - INTERVAL '1 hour',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    ('c3ddee99-9c0b-4ef8-bb6d-6bb9bd380a03', 
     'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     'MAINTENANCE_DUE', 
     'Maintenance préventive prévue dans 5 jours',
     'LOW', 
     'ACTIVE', 
     CURRENT_TIMESTAMP - INTERVAL '2 days',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- Insérer des données de test pour les notifications
INSERT INTO service_evenements.notifications_log 
    (id, alert_id, destinataire, canal, message, statut_envoi, horodatage, created_at, updated_at)
VALUES 
    ('d4eeff99-9c0b-4ef8-bb6d-6bb9bd380a04', 
     'b2ccdd99-9c0b-4ef8-bb6d-6bb9bd380a02', 
     'jean.dupont@example.com', 
     'EMAIL', 
     'Alerte vitesse: Excès de vitesse détecté sur véhicule EF-456-GH',
     'SENT', 
     CURRENT_TIMESTAMP - INTERVAL '55 minutes',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    ('e5ffgg99-9c0b-4ef8-bb6d-6bb9bd380a05', 
     'b2ccdd99-9c0b-4ef8-bb6d-6bb9bd380a02', 
     '+33612345678', 
     'SMS', 
     'ALERTE: Excès de vitesse détecté - Vitesse: 85 km/h',
     'SENT', 
     CURRENT_TIMESTAMP - INTERVAL '50 minutes',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- VÉRIFICATION
-- -----------------------------------------------------------------------------

-- Vérifier les nouvelles colonnes dans maintenance_records
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'service_maintenance' 
AND table_name = 'maintenance_records'
AND column_name IN ('type_maintenance', 'cout_estime')
ORDER BY column_name;

-- Vérifier les tables du schéma service_evenements
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'service_evenements'
ORDER BY table_name;

-- Compter les lignes de test
SELECT 'Alertes' AS table_name, COUNT(*) AS row_count 
FROM service_evenements.alerts
UNION ALL
SELECT 'Notifications', COUNT(*) 
FROM service_evenements.notifications_log
UNION ALL
SELECT 'Maintenance (PREVENTIVE)', COUNT(*) 
FROM service_maintenance.maintenance_records
WHERE type_maintenance = 'PREVENTIVE';


-- =============================================================================
-- END OF MIGRATION V005
-- =============================================================================

