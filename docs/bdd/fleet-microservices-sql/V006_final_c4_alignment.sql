-- =============================================================================
-- Fleet Management Microservices - Migration V006
-- Alignement Final C4 (Niveaux 3 et 4)
-- =============================================================================
-- Ce script complète les schéma pour соответствие aux diagrammes C4
-- Compatible avec PostgreSQL 14+ et PostGIS
-- =============================================================================

-- =============================================================================
-- PARTIE 1 : SERVICE VÉHICULES (C4 Niveau 3)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Ajout de colonnes à la table vehicles
-- -----------------------------------------------------------------------------

-- Ajouter type_carburant si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_vehicles' 
        AND table_name = 'vehicles' 
        AND column_name = 'type_carburant'
    ) THEN
        ALTER TABLE service_vehicles.vehicles
        ADD COLUMN type_carburant VARCHAR(50);
    END IF;
END $$;

-- Ajouter consommation_moyenne si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_vehicles' 
        AND table_name = 'vehicles' 
        AND column_name = 'consommation_moyenne'
    ) THEN
        ALTER TABLE service_vehicles.vehicles
        ADD COLUMN consommation_moyenne FLOAT;
    END IF;
END $$;

-- Ajouter date_derniere_revision si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_vehicles' 
        AND table_name = 'vehicles' 
        AND column_name = 'date_derniere_revision'
    ) THEN
        ALTER TABLE service_vehicles.vehicles
        ADD COLUMN date_derniere_revision DATE;
    END IF;
END $$;

-- Créer index sur type_carburant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_vehicles' 
        AND tablename = 'vehicles' 
        AND indexname = 'idx_vehicles_type_carburant'
    ) THEN
        CREATE INDEX idx_vehicles_type_carburant 
            ON service_vehicles.vehicles(type_carburant);
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Création table vehicle_specs (spécifications techniques)
-- -----------------------------------------------------------------------------

-- Créer le type ENUM pour le type de carburant (si pas existant)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fuel_type_enum') THEN
        CREATE TYPE fuel_type_enum AS ENUM (
            'ESSENCE',
            'DIESEL',
            'ELECTRIQUE',
            'HYBRIDE',
            'GPL',
            'HYDROGENE'
        );
    END IF;
END $$;

-- Créer la table vehicle_specs
CREATE TABLE IF NOT EXISTS service_vehicles.vehicle_specs (
    -- Primary Key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Clé étrangère vers vehicles
    vehicle_id UUID NOT NULL UNIQUE,
    
    -- Spécifications techniques
    puissance_ch INTEGER,                    -- Puissance en chevaux
    capacite_reservoir_litre FLOAT,          -- Capacité du réservoir en litres
    longueur_mm INTEGER,                     -- Longueur en mm
    largeur_mm INTEGER,                      -- Largeur en mm
    hauteur_mm INTEGER,                      -- Hauteur en mm
    poids_kg INTEGER,                        -- Poids en kg
    type_carburant fuel_type_enum,           -- Type de carburant
    
    -- Audit columns
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Contrainte de clé étrangère
    CONSTRAINT fk_vehicle_specs_vehicle 
        FOREIGN KEY (vehicle_id) 
        REFERENCES service_vehicles.vehicles(id)
        ON DELETE CASCADE
);

-- Index pour vehicle_specs
CREATE INDEX IF NOT EXISTS idx_vehicle_specs_vehicle_id 
    ON service_vehicles.vehicle_specs(vehicle_id);

CREATE INDEX IF NOT EXISTS idx_vehicle_specs_puissance 
    ON service_vehicles.vehicle_specs(puissance_ch);

-- Trigger pour updated_at
CREATE OR REPLACE FUNCTION service_vehicles.update_vehicle_specs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_vehicle_specs_updated_at 
    BEFORE UPDATE ON service_vehicles.vehicle_specs
    FOR EACH ROW 
    EXECUTE FUNCTION service_vehicles.update_vehicle_specs_updated_at();


-- =============================================================================
-- PARTIE 2 : SERVICE CONDUCTEURS (C4 Niveau 3)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Ajout de colonnes à la table drivers
-- -----------------------------------------------------------------------------

-- Ajouter statut_permis si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_conducteurs' 
        AND table_name = 'drivers' 
        AND column_name = 'statut_permis'
    ) THEN
        ALTER TABLE service_conducteurs.drivers
        ADD COLUMN statut_permis BOOLEAN NOT NULL DEFAULT TRUE;
    END IF;
END $$;

-- Ajouter categorie_permis si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_conducteurs' 
        AND table_name = 'drivers' 
        AND column_name = 'categorie_permis'
    ) THEN
        ALTER TABLE service_conducteurs.drivers
        ADD COLUMN categorie_permis VARCHAR(10);
    END IF;
END $$;

-- Créer index sur categorie_permis
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_conducteurs' 
        AND tablename = 'drivers' 
        AND indexname = 'idx_drivers_categorie_permis'
    ) THEN
        CREATE INDEX idx_drivers_categorie_permis 
            ON service_conducteurs.drivers(categorie_permis);
    END IF;
END $$;

-- Créer index sur statut_permis
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_conducteurs' 
        AND tablename = 'drivers' 
        AND indexname = 'idx_drivers_statut_permis'
    ) THEN
        CREATE INDEX idx_drivers_statut_permis 
            ON service_conducteurs.drivers(statut_permis);
    END IF;
END $$;


-- =============================================================================
-- PARTIE 3 : SERVICE LOCALISATION & GEOFENCING (C4 Niveau 4)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Activation de PostGIS
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS postgis;


-- -----------------------------------------------------------------------------
-- Ajout de la colonne géométrique geom
-- -----------------------------------------------------------------------------

-- Ajouter la colonne geom si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_localisation' 
        AND table_name = 'vehicle_locations' 
        AND column_name = 'geom'
    ) THEN
        ALTER TABLE service_localisation.vehicle_locations
        ADD COLUMN geom GEOMETRY(Point, 4326);
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Création de la fonction de mise à jour automatique du geom
-- -----------------------------------------------------------------------------

-- Fonction pour mettre à jour geom à partir de latitude/longitude
CREATE OR REPLACE FUNCTION service_localisation.update_geom_from_coords()
RETURNS TRIGGER AS $$
BEGIN
    -- Mettre à jour la colonne geom si latitude et longitude sont présentes
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.geom := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Créer le trigger si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.triggers 
        WHERE trigger_name = 'update_geom_from_coords'
    ) THEN
        CREATE TRIGGER update_geom_from_coords
            BEFORE INSERT OR UPDATE ON service_localisation.vehicle_locations
            FOR EACH ROW
            EXECUTE FUNCTION service_localisation.update_geom_from_coords();
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Index spatial GIST pour le géofencing
-- -----------------------------------------------------------------------------

-- Créer l'index spatial GIST si pas existant
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_localisation' 
        AND tablename = 'vehicle_locations' 
        AND indexname = 'idx_vehicle_locations_geom_gist'
    ) THEN
        CREATE INDEX idx_vehicle_locations_geom_gist 
            ON service_localisation.vehicle_locations 
            USING GIST (geom);
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Mise à jour des données existantes avec geom
-- -----------------------------------------------------------------------------

-- Mettre à jour les lignes existantes pour populate geom
UPDATE service_localisation.vehicle_locations
SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
WHERE geom IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL;


-- =============================================================================
-- PARTIE 4 : SERVICE ÉVÉNEMENTS (Rappel - alignement C4)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Mise à jour de la table alerts pour соответствие C4
-- -----------------------------------------------------------------------------

-- Créer le type ENUM pour le type d'alerte C4 (si pas existant)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type_c4_enum') THEN
        CREATE TYPE alert_type_c4_enum AS ENUM (
            'GEOFENCING',
            'SPEED'
        );
    END IF;
END $$;

-- Ajouter colonne type si elle n'existe pas (ou la renommer si nécessaire)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_evenements' 
        AND table_name = 'alerts' 
        AND column_name = 'type'
    ) THEN
        -- Vérifier si type_alerte existe déjà et la renommer
        IF EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'service_evenements' 
            AND table_name = 'alerts' 
            AND column_name = 'type_alerte'
        ) THEN
            ALTER TABLE service_evenements.alerts 
                RENAME COLUMN type_alerte TO type;
        ELSE
            ALTER TABLE service_evenements.alerts
            ADD COLUMN type alert_type_c4_enum NOT NULL DEFAULT 'SPEED';
        END IF;
    END IF;
END $$;

-- Ajouter colonne timestamp si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'service_evenements' 
        AND table_name = 'alerts' 
        AND column_name = 'timestamp'
    ) THEN
        -- Vérifier si date_alerte existe déjà et la renommer
        IF EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'service_evenements' 
            AND table_name = 'alerts' 
            AND column_name = 'date_alerte'
        ) THEN
            ALTER TABLE service_evenements.alerts 
                RENAME COLUMN date_alerte TO timestamp;
        ELSE
            ALTER TABLE service_evenements.alerts
            ADD COLUMN timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
        END IF;
    END IF;
END $$;

-- Créer index sur timestamp
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'service_evenements' 
        AND tablename = 'alerts' 
        AND indexname = 'idx_alerts_timestamp'
    ) THEN
        CREATE INDEX idx_alerts_timestamp 
            ON service_evenements.alerts(timestamp DESC);
    END IF;
END $$;


-- =============================================================================
-- PARTIE 5 : PERMISSIONS & SÉCURITÉ
-- -----------------------------------------------------------------------------

-- Accorder les permissions sur les nouvelles tables/colonnes

-- Permissions pour service_vehicles
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA service_vehicles TO role_service_vehicles;

-- Permissions pour service_conducteurs  
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA service_conducteurs TO role_service_conducteurs;

-- Permissions pour service_localisation
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA service_localisation TO role_service_localisation;

-- Permissions pour service_evenements
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA service_evenements TO role_service_evenements;

-- Permissions par défaut pour les nouveaux objets
ALTER DEFAULT PRIVILEGES IN SCHEMA service_vehicles 
    GRANT SELECT, INSERT, UPDATE ON TABLES TO role_service_vehicles;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_conducteurs 
    GRANT SELECT, INSERT, UPDATE ON TABLES TO role_service_conducteurs;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_localisation 
    GRANT SELECT, INSERT, UPDATE ON TABLES TO role_service_localisation;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_evenements 
    GRANT SELECT, INSERT, UPDATE ON TABLES TO role_service_evenements;


-- =============================================================================
-- PARTIE 6 : DONNÉES DE TEST COMPLÉMENTAIRES
-- -----------------------------------------------------------------------------

-- Insérer des spécifications techniques pour les véhicules de test
INSERT INTO service_vehicles.vehicle_specs 
    (id, vehicle_id, puissance_ch, capacite_reservoir_litre, longueur_mm, largeur_mm, hauteur_mm, poids_kg, type_carburant, created_at, updated_at)
VALUES 
    ('f6gghh99-9c0b-4ef8-bb6d-6bb9bd380a06', 
     'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     150, 50, 4885, 1840, 1455, 1620, 'ESSENCE',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('g7hhii99-9c0b-4ef8-bb6d-6bb9bd380a07', 
     'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     130, 45, 4650, 1800, 1420, 1550, 'DIESEL',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (vehicle_id) DO NOTHING;

-- Mettre à jour les véhicules avec les nouvelles colonnes
UPDATE service_vehicles.vehicles 
SET type_carburant = 'ESSENCE', 
    consommation_moyenne = 7.5, 
    date_derniere_revision = CURRENT_DATE - INTERVAL '90 days'
WHERE immatriculation = 'AB-123-CD';

UPDATE service_vehicles.vehicles 
SET type_carburant = 'DIESEL', 
    consommation_moyenne = 6.2, 
    date_derniere_revision = CURRENT_DATE - INTERVAL '30 days'
WHERE immatriculation = 'EF-456-GH';

-- Mettre à jour les conducteurs avec les nouvelles colonnes
UPDATE service_conducteurs.drivers 
SET statut_permis = TRUE, 
    categorie_permis = 'B'
WHERE numéro_permis = 'PERMIS001';

UPDATE service_conducteurs.drivers 
SET statut_permis = TRUE, 
    categorie_permis = 'B'
WHERE numéro_permis = 'PERMIS002';

-- Insérer des alertes de type GEOFENCING pour tester
INSERT INTO service_evenements.alerts 
    (id, vehicle_id, type, description, niveau_severity, statut, timestamp, created_at, updated_at)
VALUES 
    ('h8ii jj99-9c0b-4ef8-bb6d-6bb9bd380a08', 
     'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     'GEOFENCING', 
     'Sortie de zone géographiquement définie - Zone dépôt principal',
     'MEDIUM', 
     'ACTIVE', 
     CURRENT_TIMESTAMP - INTERVAL '30 minutes',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- Mettre à jour les localisations avec la colonne geom
INSERT INTO service_localisation.vehicle_locations 
    (time, vehicle_id, latitude, longitude, vitesse, geom, précision, cap)
VALUES 
    (CURRENT_TIMESTAMP, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     48.8566, 2.3522, 0, 
     ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326),
     10, 0)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- VÉRIFICATION
-- -----------------------------------------------------------------------------

-- Vérifier les nouvelles colonnes vehicles
SELECT column_name, data_type 
FROM information_schema.columns
WHERE table_schema = 'service_vehicles' 
AND table_name = 'vehicles'
AND column_name IN ('type_carburant', 'consommation_moyenne', 'date_derniere_revision')
ORDER BY column_name;

-- Vérifier vehicle_specs
SELECT COUNT(*) AS vehicle_specs_count 
FROM service_vehicles.vehicle_specs;

-- Vérifier les colonnes drivers
SELECT column_name, data_type 
FROM information_schema.columns
WHERE table_schema = 'service_conducteurs' 
AND table_name = 'drivers'
AND column_name IN ('statut_permis', 'categorie_permis')
ORDER BY column_name;

-- Vérifier PostGIS
SELECT postgis_version();

-- Vérifier geom dans vehicle_locations
SELECT column_name, data_type 
FROM information_schema.columns
WHERE table_schema = 'service_localisation' 
AND table_name = 'vehicle_locations'
AND column_name = 'geom';

-- Vérifier les alertes
SELECT type, COUNT(*) 
FROM service_evenements.alerts
GROUP BY type;


-- =============================================================================
-- END OF MIGRATION V006
-- =============================================================================

