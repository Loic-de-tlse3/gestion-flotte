-- =============================================================================
-- Fleet Management Microservices - Migration V004
-- Test Data for Development and Verification
-- =============================================================================
-- This file contains sample data for testing the database schemas
-- Use only in development/testing environments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Insert test data into service_vehicles
-- -----------------------------------------------------------------------------

INSERT INTO service_vehicles.vehicles 
    (id, immatriculation, marque, modèle, statut, created_at, updated_at)
VALUES 
    ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'AB-123-CD', 'Toyota', 'Camry', 'AVAILABLE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 'EF-456-GH', 'Honda', 'Civic', 'IN_USE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('c2ggde99-9c0b-4ef8-bb6d-6bb9bd380a33', 'IJ-789-KL', 'Ford', 'Focus', 'MAINTENANCE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('d3hhef99-9c0b-4ef8-bb6d-6bb9bd380a44', 'MN-012-OP', 'Renault', 'Clio', 'AVAILABLE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('e4iifg99-9c0b-4ef8-bb6d-6bb9bd380a55', 'QR-345-ST', 'Peugeot', '208', 'RETIRED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (immatriculation) DO NOTHING;


-- -----------------------------------------------------------------------------
-- Insert test data into service_conducteurs.drivers
-- -----------------------------------------------------------------------------

INSERT INTO service_conducteurs.drivers 
    (id, keycloak_id, numéro_permis, nom, prénom, téléphone, email, created_at, updated_at)
VALUES 
    ('f5jjgh99-9c0b-4ef8-bb6d-6bb9bd380a11', 'keycloak-user-001', 'PERMIS001', 'Dupont', 'Jean', '+33 6 12 34 56 78', 'jean.dupont@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('g6kkhi99-9c0b-4ef8-bb6d-6bb9bd380a22', 'keycloak-user-002', 'PERMIS002', 'Martin', 'Sophie', '+33 6 23 45 67 89', 'sophie.martin@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('h7llij99-9c0b-4ef8-bb6d-6bb9bd380a33', 'keycloak-user-003', 'PERMIS003', 'Bernard', 'Paul', '+33 6 34 56 78 90', 'paul.bernard@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('i8mmjk99-9c0b-4ef8-bb6d-6bb9bd380a44', 'keycloak-user-004', 'PERMIS004', 'Durand', 'Marie', '+33 6 45 67 89 01', 'marie.durand@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (keycloak_id) DO NOTHING;


-- -----------------------------------------------------------------------------
-- Insert test data into service_conducteurs.assignments
-- -----------------------------------------------------------------------------

INSERT INTO service_conducteurs.assignments 
    (id, driver_id, vehicle_id, date_début, date_fin, motif, created_at, updated_at)
VALUES 
    ('j9nnkl99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     'f5jjgh99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     CURRENT_TIMESTAMP - INTERVAL '5 days', 
     NULL, 
     'Mission commerciale Paris-Lyon',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    ('k9oolm99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     'g6kkhi99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     CURRENT_TIMESTAMP - INTERVAL '2 days', 
     NULL, 
     'Livraison urbaine',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    -- Historical assignment (completed)
    ('l9ppnm99-9c0b-4ef8-bb6d-6bb9bd380a33', 
     'h7llij99-9c0b-4ef8-bb6d-6bb9bd380a33', 
     'd3hhef99-9c0b-4ef8-bb6d-6bb9bd380a44', 
     CURRENT_TIMESTAMP - INTERVAL '30 days', 
     CURRENT_TIMESTAMP - INTERVAL '25 days', 
     'Formation nouveaux employés',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;


-- -----------------------------------------------------------------------------
-- Insert test data into service_localisation.vehicle_locations
-- -----------------------------------------------------------------------------

INSERT INTO service_localisation.vehicle_locations 
    (time, vehicle_id, latitude, longitude, vitesse, précision, cap)
VALUES 
    -- Vehicle AB-123-CD locations
    (CURRENT_TIMESTAMP - INTERVAL '1 hour', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 48.8566, 2.3522, 0, 10, 0),
    (CURRENT_TIMESTAMP - INTERVAL '45 minutes', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 48.8570, 2.3530, 25, 8, 45),
    (CURRENT_TIMESTAMP - INTERVAL '30 minutes', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 48.8580, 2.3545, 35, 5, 90),
    (CURRENT_TIMESTAMP - INTERVAL '15 minutes', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 48.8590, 2.3560, 40, 5, 90),
    (CURRENT_TIMESTAMP, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 48.8600, 2.3575, 0, 10, 0),
    
    -- Vehicle EF-456-GH locations (in use)
    (CURRENT_TIMESTAMP - INTERVAL '2 hours', 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 45.7640, 4.8357, 0, 12, 0),
    (CURRENT_TIMESTAMP - INTERVAL '1 hour', 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 45.7650, 4.8370, 50, 6, 180),
    (CURRENT_TIMESTAMP - INTERVAL '30 minutes', 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 45.7660, 4.8385, 45, 5, 170),
    (CURRENT_TIMESTAMP, 'b1ffcd99-9c0b-4ef8-bb6d-6bb9bd380a22', 45.7670, 4.8400, 30, 7, 175)
ON CONFLICT DO NOTHING;


-- -----------------------------------------------------------------------------
-- Insert test data into service_maintenance.maintenance_records
-- -----------------------------------------------------------------------------

INSERT INTO service_maintenance.maintenance_records 
    (id, vehicle_id, type_maintenance, description, coût, date_début, date_fin, statut, created_at, updated_at)
VALUES 
    ('m9qqop99-9c0b-4ef8-bb6d-6bb9bd380a11', 
     'c2ggde99-9c0b-4ef8-bb6d-6bb9bd380a33', 
     'Vidange moteur', 
     'Vidange huile moteur + filtre', 
     150.00, 
     CURRENT_TIMESTAMP - INTERVAL '3 days', 
     CURRENT_TIMESTAMP - INTERVAL '2 days', 
     'TERMINÉ',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    ('n9rrpq99-9c0b-4ef8-bb6d-6bb9bd380a22', 
     'c2ggde99-9c0b-4ef8-bb6d-6bb9bd380a33', 
     'Révision freins', 
     'Contrôle et remplacement plaquettes avant', 
     320.00, 
     CURRENT_TIMESTAMP - INTERVAL '1 days', 
     NULL, 
     'EN_COURS',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP),
    ('o9ssqr99-9c0b-4ef8-bb6d-6bb9bd380a33', 
     'e4iifg99-9c0b-4ef8-bb6d-6bb9bd380a55', 
     'Contrôle technique', 
     'Renouvellement CT', 
     80.00, 
     CURRENT_TIMESTAMP - INTERVAL '60 days', 
     CURRENT_TIMESTAMP - INTERVAL '60 days', 
     'TERMINÉ',
     CURRENT_TIMESTAMP, 
     CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- Verification Queries
-- =============================================================================

-- Query 1: All vehicles
SELECT 'Vehicles' AS table_name, COUNT(*) AS row_count 
FROM service_vehicles.vehicles
UNION ALL
-- Query 2: All drivers
SELECT 'Drivers' AS table_name, COUNT(*) AS row_count 
FROM service_conducteurs.drivers
UNION ALL
-- Query 3: All assignments
SELECT 'Assignments' AS table_name, COUNT(*) AS row_count 
FROM service_conducteurs.assignments
UNION ALL
-- Query 4: All locations
SELECT 'Locations' AS table_name, COUNT(*) AS row_count 
FROM service_localisation.vehicle_locations
UNION ALL
-- Query 5: All maintenance records
SELECT 'Maintenance' AS table_name, COUNT(*) AS row_count 
FROM service_maintenance.maintenance_records;


-- Query: Active assignments with vehicle and driver details
SELECT 
    v.immatriculation,
    v.marque || ' ' || v.modèle AS véhicule,
    d.nom || ' ' || d.prénom AS conducteur,
    a.date_début AS depuis
FROM service_conducteurs.assignments a
JOIN service_vehicles.vehicles v ON a.vehicle_id = v.id
JOIN service_conducteurs.drivers d ON a.driver_id = d.id
WHERE a.date_fin IS NULL;


-- =============================================================================
-- END OF MIGRATION V004
-- =============================================================================

