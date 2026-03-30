-- =============================================================================
-- Fleet Management Microservices - Migration V002
-- Database Roles and Permissions Setup
-- =============================================================================
-- This file creates database roles for each microservice
-- and grants appropriate permissions following the principle of least privilege
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Create roles for each microservice
-- -----------------------------------------------------------------------------

-- Role for vehicle service
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_service_vehicles') THEN
        CREATE ROLE role_service_vehicles WITH LOGIN PASSWORD 'vehicles_secure_password';
    END IF;
END $$;

-- Role for driver service
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_service_conducteurs') THEN
        CREATE ROLE role_service_conducteurs WITH LOGIN PASSWORD 'conducteurs_secure_password';
    END IF;
END $$;

-- Role for location service
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_service_localisation') THEN
        CREATE ROLE role_service_localisation WITH LOGIN PASSWORD 'localisation_secure_password';
    END IF;
END $$;

-- Role for maintenance service
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_service_maintenance') THEN
        CREATE ROLE role_service_maintenance WITH LOGIN PASSWORD 'maintenance_secure_password';
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Grant permissions for each service schema
-- -----------------------------------------------------------------------------

-- Vehicle service permissions
GRANT USAGE ON SCHEMA service_vehicles TO role_service_vehicles;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA service_vehicles TO role_service_vehicles;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service_vehicles TO role_service_vehicles;

-- Driver service permissions
GRANT USAGE ON SCHEMA service_conducteurs TO role_service_conducteurs;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA service_conducteurs TO role_service_conducteurs;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service_conducteurs TO role_service_conducteurs;

-- Location service permissions (read-heavy, write for data ingestion)
GRANT USAGE ON SCHEMA service_localisation TO role_service_localisation;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA service_localisation TO role_service_localisation;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service_localisation TO role_service_localisation;

-- Maintenance service permissions
GRANT USAGE ON SCHEMA service_maintenance TO role_service_maintenance;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA service_maintenance TO role_service_maintenance;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service_maintenance TO role_service_maintenance;


-- -----------------------------------------------------------------------------
-- Grant read-only access to reporting role (if needed)
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_fleet_reporter') THEN
        CREATE ROLE role_fleet_reporter WITH LOGIN PASSWORD 'reporter_secure_password';
    END IF;
END $$;

GRANT USAGE ON SCHEMA service_vehicles TO role_fleet_reporter;
GRANT USAGE ON SCHEMA service_conducteurs TO role_fleet_reporter;
GRANT USAGE ON SCHEMA service_localisation TO role_fleet_reporter;
GRANT USAGE ON SCHEMA service_maintenance TO role_fleet_reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA service_vehicles TO role_fleet_reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA service_conducteurs TO role_fleet_reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA service_localisation TO role_fleet_reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA service_maintenance TO role_fleet_reporter;
GRANT SELECT ON public.vw_active_assignments TO role_fleet_reporter;


-- -----------------------------------------------------------------------------
-- Default permissions for future objects
-- -----------------------------------------------------------------------------

-- Alter default privileges for vehicle service
ALTER DEFAULT PRIVILEGES IN SCHEMA service_vehicles 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_service_vehicles;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_vehicles 
    GRANT USAGE, SELECT ON SEQUENCES TO role_service_vehicles;

-- Alter default privileges for driver service
ALTER DEFAULT PRIVILEGES IN SCHEMA service_conducteurs 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_service_conducteurs;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_conducteurs 
    GRANT USAGE, SELECT ON SEQUENCES TO role_service_conducteurs;

-- Alter default privileges for location service
ALTER DEFAULT PRIVILEGES IN SCHEMA service_localisation 
    GRANT SELECT, INSERT ON TABLES TO role_service_localisation;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_localisation 
    GRANT USAGE, SELECT ON SEQUENCES TO role_service_localisation;

-- Alter default privileges for maintenance service
ALTER DEFAULT PRIVILEGES IN SCHEMA service_maintenance 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_service_maintenance;
ALTER DEFAULT PRIVILEGES IN SCHEMA service_maintenance 
    GRANT USAGE, SELECT ON SEQUENCES TO role_service_maintenance;


-- =============================================================================
-- END OF MIGRATION V002
-- =============================================================================

