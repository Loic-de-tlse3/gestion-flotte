const pool = require('../config/db');

const baseSelect = `
  SELECT
    id::text AS id,
    immatriculation,
    marque,
    "modèle" AS modele,
    statut::text AS statut
  FROM service_vehicles.vehicles
`;

const mapRowToVehicle = (row) => ({
  id: row.id,
  immatriculation: row.immatriculation,
  marque: row.marque,
  modele: row.modele,
  statut: row.statut,
});

const mapVehicleToDb = (vehicle) => ({
  id: vehicle.id,
  immatriculation: vehicle.immatriculation,
  marque: vehicle.marque,
  modele: vehicle.modele,
  statut: vehicle.statut,
});

const findAll = async () => {
  const { rows } = await pool.query(`${baseSelect} ORDER BY created_at DESC`);
  return rows.map(mapRowToVehicle);
};

const findById = async (id) => {
  const { rows } = await pool.query(`${baseSelect} WHERE id = $1::uuid`, [id]);
  if (rows.length === 0) {
    return null;
  }

  return mapRowToVehicle(rows[0]);
};

const exists = async (id) => {
  const { rows } = await pool.query('SELECT 1 FROM service_vehicles.vehicles WHERE id = $1::uuid LIMIT 1', [id]);
  return rows.length > 0;
};

const create = async (vehicle) => {
  const dbVehicle = mapVehicleToDb(vehicle);

  try {
    const query = `
      INSERT INTO service_vehicles.vehicles (
        id,
        immatriculation,
        marque,
        "modèle",
        statut
      ) VALUES (
        $1::uuid,
        $2,
        $3,
        $4,
        $5::vehicle_status_enum
      )
      RETURNING
        id::text AS id,
        immatriculation,
        marque,
        "modèle" AS modele,
        statut::text AS statut
    `;

    const values = [
      dbVehicle.id,
      dbVehicle.immatriculation,
      dbVehicle.marque,
      dbVehicle.modele,
      dbVehicle.statut,
    ];

    const { rows } = await pool.query(query, values);
    return mapRowToVehicle(rows[0]);
  } catch (error) {
    if (error.code === '23505') {
      const conflictError = new Error('Vehicle immatriculation already exists');
      conflictError.status = 409;
      throw conflictError;
    }

    throw error;
  }
};

const update = async (id, vehicle) => {
  const dbVehicle = mapVehicleToDb(vehicle);

  try {
    const query = `
      UPDATE service_vehicles.vehicles
      SET
        immatriculation = $2,
        marque = $3,
        "modèle" = $4,
        statut = $5::vehicle_status_enum
      WHERE id = $1::uuid
      RETURNING
        id::text AS id,
        immatriculation,
        marque,
        "modèle" AS modele,
        statut::text AS statut
    `;

    const values = [
      id,
      dbVehicle.immatriculation,
      dbVehicle.marque,
      dbVehicle.modele,
      dbVehicle.statut,
    ];

    const { rows } = await pool.query(query, values);
    if (rows.length === 0) {
      return null;
    }

    return mapRowToVehicle(rows[0]);
  } catch (error) {
    if (error.code === '23505') {
      const conflictError = new Error('Vehicle immatriculation already exists');
      conflictError.status = 409;
      throw conflictError;
    }

    throw error;
  }
};

const updateStatus = async (id, status) => {
  const query = `
    UPDATE service_vehicles.vehicles
    SET statut = $2::vehicle_status_enum
    WHERE id = $1::uuid
    RETURNING
      id::text AS id,
      immatriculation,
      marque,
      "modèle" AS modele,
      statut::text AS statut
  `;

  const { rows } = await pool.query(query, [id, status]);
  if (rows.length === 0) {
    return null;
  }

  return mapRowToVehicle(rows[0]);
};

const remove = async (id) => {
  const { rowCount } = await pool.query('DELETE FROM service_vehicles.vehicles WHERE id = $1::uuid', [id]);
  return rowCount > 0;
};

module.exports = {
  findAll,
  findById,
  exists,
  create,
  update,
  updateStatus,
  remove,
};