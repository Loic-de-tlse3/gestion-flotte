-- =============================================================================
-- Fleet Management Microservices - PostgreSQL Database Schema
-- Master 1 GIL - Semaine 1 Project
-- =============================================================================
-- This file contains the initial setup for all microservices schemas
-- Compatible with PostgreSQL 14+ and TimescaleDB
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SCHEMA: service_vehicles (Vehicle Management Service)
-- -----------------------------------------------------------------------------
-- This schema contains all vehicle-related data, isolated from other services
-- -----------------------------------------------------------------------------

-- Create schema for vehicles service
CREATE SCHEMA IF NOT EXISTS service_vehicles;

-- Create ENUM type for vehicle status
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_status_enum') THEN
        CREATE TYPE vehicle_status_enum AS ENUM (
            'AVAILABLE',
            'IN_USE',
            'MAINTENANCE',
            'RETIRED'
        );
    END IF;
END $$;

-- Create vehicles table
CREATE TABLE IF NOT EXISTS service_vehicles.vehicles (
    -- Primary Key: UUID for Kafka/GraphQL compatibility
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Vehicle identification
    immatriculation VARCHAR(20) NOT NULL,
    marque VARCHAR(100) NOT NULL,
    modèle VARCHAR(100) NOT NULL,
    
    -- Vehicle status (ENUM)
    statut vehicle_status_enum NOT NULL DEFAULT 'AVAILABLE',
    
    -- Audit columns with timezone
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Unique constraint on immatriculation
    CONSTRAINT uk_vehicles_immatriculation UNIQUE (immatriculation)
);

-- Create index on immatriculation for fast lookups
CREATE INDEX IF NOT EXISTS idx_vehicles_immatriculation 
    ON service_vehicles.vehicles(immatriculation);

-- Create index on statut for filtering
CREATE INDEX IF NOT EXISTS idx_vehicles_statut 
    ON service_vehicles.vehicles(statut);

-- Create index on marque for filtering
CREATE INDEX IF NOT EXISTS idx_vehicles_marque 
    ON service_vehicles.vehicles(marque);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION service_vehicles.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_vehicles_updated_at 
    BEFORE UPDATE ON service_vehicles.vehicles
    FOR EACH ROW 
    EXECUTE FUNCTION service_vehicles.update_updated_at_column();


-- -----------------------------------------------------------------------------
-- SCHEMA: service_conducteurs (Driver Management Service)
-- -----------------------------------------------------------------------------
-- This schema contains all driver-related data and driver-vehicle assignments
-- -----------------------------------------------------------------------------

-- Create schema for drivers service
CREATE SCHEMA IF NOT EXISTS service_conducteurs;

-- Create drivers table
CREATE TABLE IF NOT EXISTS service_conducteurs.drivers (
    -- Primary Key: UUID for Kafka/GraphQL compatibility
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Keycloak SSO integration
    keycloak_id VARCHAR(255) NOT NULL,
    
    -- Driver license information
    numéro_permis VARCHAR(50) NOT NULL,
    
    -- Optional driver details
    nom VARCHAR(100),
    prénom VARCHAR(100),
    téléphone VARCHAR(20),
    email VARCHAR(255),
    
    -- Audit columns with timezone
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Unique constraint on keycloak_id for SSO link
    CONSTRAINT uk_drivers_keycloak_id UNIQUE (keycloak_id),
    -- Unique constraint on license number
    CONSTRAINT uk_drivers_numero_permis UNIQUE (numéro_permis),
    -- Unique constraint on phone number
    CONSTRAINT uk_drivers_telephone UNIQUE (téléphone)
);

-- Create index on keycloak_id for SSO lookups
CREATE INDEX IF NOT EXISTS idx_drivers_keycloak_id 
    ON service_conducteurs.drivers(keycloak_id);

-- Create index on license number for verification
CREATE INDEX IF NOT EXISTS idx_drivers_numero_permis 
    ON service_conducteurs.drivers(numéro_permis);

-- Create index on nom/prénom for name searches
CREATE INDEX IF NOT EXISTS idx_drivers_nom_prenom 
    ON service_conducteurs.drivers(nom, prénom);

-- Create assignments table (driver-vehicle relationship)
CREATE TABLE IF NOT EXISTS service_conducteurs.assignments (
    -- Primary Key: UUID
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Foreign Keys to link with other services (stored as UUID references)
    driver_id UUID NOT NULL,
    vehicle_id UUID NOT NULL,
    
    -- Assignment details
    date_début TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date_fin TIMESTAMPTZ,
    motif TEXT,
    
    -- Audit columns with timezone
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Active assignment constraint (no overlapping active assignments for same driver)
    CONSTRAINT chk_assignments_date CHECK (
        date_fin IS NULL OR date_fin > date_début
    )
);

-- Create index on driver_id for driver assignment lookups
CREATE INDEX IF NOT EXISTS idx_assignments_driver_id 
    ON service_conducteurs.assignments(driver_id);

-- Create index on vehicle_id for vehicle assignment lookups
CREATE INDEX IF NOT EXISTS idx_assignments_vehicle_id 
    ON service_conducteurs.assignments(vehicle_id);

-- Create index on date_début for temporal queries
CREATE INDEX IF NOT EXISTS idx_assignments_date_debut 
    ON service_conducteurs.assignments(date_début);

-- Create index to find active assignments (where date_fin is NULL)
CREATE INDEX IF NOT EXISTS idx_assignments_active 
    ON service_conducteurs.assignments(driver_id, date_début) 
    WHERE date_fin IS NULL;

-- Create trigger to update updated_at timestamp for drivers
CREATE TRIGGER update_drivers_updated_at 
    BEFORE UPDATE ON service_conducteurs.drivers
    FOR EACH ROW 
    EXECUTE FUNCTION service_conducteurs.update_updated_at_driver_column();

-- Create trigger function for drivers
CREATE OR REPLACE FUNCTION service_conducteurs.update_updated_at_driver_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to update updated_at timestamp for assignments
CREATE TRIGGER update_assignments_updated_at 
    BEFORE UPDATE ON service_conducteurs.assignments
    FOR EACH ROW 
    EXECUTE FUNCTION service_conducteurs.update_updated_at_assignment_column();

-- Create trigger function for assignments
CREATE OR REPLACE FUNCTION service_conducteurs.update_updated_at_assignment_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';


-- -----------------------------------------------------------------------------
-- SCHEMA: service_localisation (Location Tracking Service)
-- -----------------------------------------------------------------------------
-- This schema uses TimescaleDB for time-series vehicle location data
-- -----------------------------------------------------------------------------

-- Create schema for localization service
CREATE SCHEMA IF NOT EXISTS service_localisation;

-- Create vehicle_locations table (will be converted to hypertable)
CREATE TABLE IF NOT EXISTS service_localisation.vehicle_locations (
    -- Time-series primary key
    time TIMESTAMPTZ NOT NULL,
    vehicle_id UUID NOT NULL,
    
    -- Location data
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    vitesse DOUBLE PRECISION,  -- in km/h
    
    -- Additional metadata
    précision DOUBLE PRECISION,  -- GPS accuracy in meters
    cap DOUBLE PRECISION,        -- heading in degrees
    
    -- Primary key for the table
    PRIMARY KEY (vehicle_id, time)
);

-- Create index on time for time-range queries
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_time 
    ON service_localisation.vehicle_locations(time DESC);

-- Create index on vehicle_id for vehicle-specific queries
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_vehicle_id 
    ON service_localisation.vehicle_locations(vehicle_id);

-- Create index for recent locations (compound)
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_recent 
    ON service_localisation.vehicle_locations(vehicle_id, time DESC);

-- Create index on vitesse for speed-based queries
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_vitesse 
    ON service_localisation.vehicle_locations(vitesse) 
    WHERE vitesse IS NOT NULL;

-- Note: The following hypertable creation should be executed AFTER TimescaleDB
-- extension is installed. Uncomment the line below when TimescaleDB is available:
-- SELECT create_hypertable('service_localisation.vehicle_locations', 'time', 
--     chunk_time_interval => INTERVAL '1 day',
--     if_not_exists => TRUE);

-- For now, create a regular table that can be converted to hypertable later
-- Add comments for documentation
COMMENT ON TABLE service_localisation.vehicle_locations IS 
    'Time-series table for vehicle GPS locations. Convert to TimescaleDB hypertable after extension installation.';
COMMENT ON COLUMN service_localisation.vehicle_locations.vitesse IS 
    'Vehicle speed in kilometers per hour';
COMMENT ON COLUMN service_localisation.vehicle_locations.précision IS 
    'GPS accuracy in meters';
COMMENT ON COLUMN service_localisation.vehicle_locations.cap IS 
    'Vehicle heading/direction in degrees (0-360)';


-- -----------------------------------------------------------------------------
-- SCHEMA: service_maintenance (Maintenance Tracking Service)
-- -----------------------------------------------------------------------------
-- Bonus: Table for tracking vehicle maintenance records
-- -----------------------------------------------------------------------------

-- Create schema for maintenance service
CREATE SCHEMA IF NOT EXISTS service_maintenance;

-- Create maintenance_records table
CREATE TABLE IF NOT EXISTS service_maintenance.maintenance_records (
    -- Primary Key: UUID
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Vehicle reference
    vehicle_id UUID NOT NULL,
    
    -- Maintenance details
    type_maintenance VARCHAR(100) NOT NULL,
    description TEXT,
    coût DECIMAL(10, 2),
    
    -- Maintenance dates
    date_début TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date_fin TIMESTAMPTZ,
    
    -- Status
    statut VARCHAR(50) NOT NULL DEFAULT 'PLANIFIÉ',
    
    -- Audit columns
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_maintenance_vehicle_id 
    ON service_maintenance.maintenance_records(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_date_debut 
    ON service_maintenance.maintenance_records(date_début);
CREATE INDEX IF NOT EXISTS idx_maintenance_statut 
    ON service_maintenance.maintenance_records(statut);

-- Create trigger
CREATE OR REPLACE FUNCTION service_maintenance.update_updated_at_maintenance()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_maintenance_updated_at 
    BEFORE UPDATE ON service_maintenance.maintenance_records
    FOR EACH ROW 
    EXECUTE FUNCTION service_maintenance.update_updated_at_maintenance();


-- =============================================================================
-- VIEW: Cross-service view for reporting (read-only, optional)
-- =============================================================================
-- This view demonstrates how data can be combined across services
-- Note: In microservices, this should only be used for read-only reporting
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.vw_active_assignments AS
SELECT 
    a.id AS assignment_id,
    a.date_début,
    a.date_fin,
    d.id AS driver_id,
    d.nom AS driver_nom,
    d.prénom AS driver_prénom,
    d.numéro_permis,
    v.id AS vehicle_id,
    v.immatriculation,
    v.marque,
    v.modèle,
    v.statut AS vehicle_statut
FROM service_conducteurs.assignments a
JOIN service_conducteurs.drivers d ON a.driver_id = d.id
JOIN service_vehicles.vehicles v ON a.vehicle_id = v.id
WHERE a.date_fin IS NULL;


-- =============================================================================
-- COMMENTS FOR DOCUMENTATION
-- =============================================================================

COMMENT ON SCHEMA service_vehicles IS 
    'Microservice schema for vehicle management - Contains vehicles table';
COMMENT ON SCHEMA service_conducteurs IS 
    'Microservice schema for driver management - Contains drivers and assignments tables';
COMMENT ON SCHEMA service_localisation IS 
    'Microservice schema for location tracking - Contains vehicle_locations for TimescaleDB';
COMMENT ON SCHEMA service_maintenance IS 
    'Microservice schema for maintenance tracking - Contains maintenance_records table';


-- =============================================================================
-- END OF INITIAL SCHEMA SETUP
-- =============================================================================

