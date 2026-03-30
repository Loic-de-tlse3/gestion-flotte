-- -----------------------------------------------------------------------------
-- Migration V007: Add unique constraint on driver phone number
-- -----------------------------------------------------------------------------
-- This migration is idempotent. It adds a unique constraint to prevent duplicate
-- phone numbers in service_conducteurs.drivers.
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uk_drivers_telephone'
    ) THEN
        ALTER TABLE service_conducteurs.drivers
            ADD CONSTRAINT uk_drivers_telephone UNIQUE (téléphone);
    END IF;
END $$;
