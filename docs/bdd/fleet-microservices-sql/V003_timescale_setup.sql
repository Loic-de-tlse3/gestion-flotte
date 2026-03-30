-- =============================================================================
-- Fleet Management Microservices - Migration V003
-- TimescaleDB Hypertable Setup for Vehicle Locations
-- =============================================================================
-- This file converts the vehicle_locations table to a TimescaleDB hypertable
-- for optimal time-series performance
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Verify TimescaleDB extension is available
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        RAISE NOTICE 'TimescaleDB extension is not installed. Skipping hypertable creation.';
    ELSE
        RAISE NOTICE 'TimescaleDB extension detected. Proceeding with hypertable creation.';
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Create TimescaleDB hypertable (if extension is available)
-- -----------------------------------------------------------------------------

-- This will create a hypertable partitioned by time
-- Chunks are created for 1 day intervals
SELECT create_hypertable(
    'service_localisation.vehicle_locations',
    'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE,
    migrate_data => TRUE
);


-- -----------------------------------------------------------------------------
-- Add compression for older data (retention policy preparation)
-- -----------------------------------------------------------------------------

-- Enable compression on the hypertable
ALTER TABLE service_localisation.vehicle_locations 
    SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'vehicle_id'
    );


-- -----------------------------------------------------------------------------
-- Add compression policy (compress chunks older than 7 days)
-- -----------------------------------------------------------------------------

SELECT add_compression_policy(
    'service_localisation.vehicle_locations',
    INTERVAL '7 days',
    if_not_exists => TRUE
);


-- -----------------------------------------------------------------------------
-- Add retention policy (delete data older than 1 year)
-- -----------------------------------------------------------------------------

SELECT add_retention_policy(
    'service_localisation.vehicle_locations',
    INTERVAL '1 year',
    if_not_exists => TRUE
);


-- -----------------------------------------------------------------------------
-- Create continuous aggregate for hourly statistics (optional)
-- -----------------------------------------------------------------------------

-- Create a continuous aggregate for vehicle hourly statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS service_localisation.vehicle_hourly_stats
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', time) AS hour,
    vehicle_id,
    AVG(latitude) AS avg_latitude,
    AVG(longitude) AS avg_longitude,
    AVG(vitesse) AS avg_vitesse,
    MAX(vitesse) AS max_vitesse,
    MIN(vitesse) AS min_vitesse,
    COUNT(*) AS location_count
FROM service_localisation.vehicle_locations
GROUP BY hour, vehicle_id
WITH NO DATA;

-- Add refresh policy for the continuous aggregate
SELECT add_continuous_aggregate_policy(
    'service_localisation.vehicle_hourly_stats',
    start_offset => INTERVAL '2 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Create indexes on the continuous aggregate
CREATE INDEX IF NOT EXISTS idx_vehicle_hourly_stats_hour 
    ON service_localisation.vehicle_hourly_stats(hour DESC);
CREATE INDEX IF NOT EXISTS idx_vehicle_hourly_stats_vehicle 
    ON service_localisation.vehicle_hourly_stats(vehicle_id);


-- -----------------------------------------------------------------------------
-- Add additional indexes for common query patterns
-- -----------------------------------------------------------------------------

-- Index for speed monitoring queries
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_speed_analysis 
    ON service_localisation.vehicle_locations(vehicle_id, time DESC, vitesse);

-- Index for geofencing queries
CREATE INDEX IF NOT EXISTS idx_vehicle_locations_geofence 
    ON service_localisation.vehicle_locations(time DESC) 
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;


-- =============================================================================
-- END OF MIGRATION V003
-- =============================================================================

