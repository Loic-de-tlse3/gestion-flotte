const { randomUUID } = require('crypto');
const vehicleRepository = require('../repositories/vehicleRepository');
const { publishVehicleEvent } = require('../kafka/producer');

const IMMEDIATE_MAINTENANCE_THRESHOLD_HOURS = Number(process.env.IMMEDIATE_MAINTENANCE_THRESHOLD_HOURS || 24);

const isUuid = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const normalizeVehicle = (payload, id) => ({
  id,
  immatriculation: payload.immatriculation.trim(),
  marque: payload.marque.trim(),
  modele: payload.modele.trim(),
  statut: payload.statut,
});

const listVehicles = () => vehicleRepository.findAll();

const getVehicleById = (id) => vehicleRepository.findById(id);

const createVehicle = async (payload) => {
  const requestedId = typeof payload.id === 'string' ? payload.id.trim() : '';
  const id = requestedId || randomUUID();

  if (!isUuid(id)) {
    const error = new Error('Vehicle id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  if (await vehicleRepository.exists(id)) {
    const error = new Error('Vehicle id already exists');
    error.status = 409;
    throw error;
  }

  const vehicle = normalizeVehicle(payload, id);
  const createdVehicle = await vehicleRepository.create(vehicle);

  try {
    await publishVehicleEvent({
      eventType: 'vehicule.cree',
      vehicle: createdVehicle,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour vehicule.cree:', error.message);
  }

  return createdVehicle;
};

const updateVehicle = async (id, payload) => {
  if (!isUuid(id)) {
    const error = new Error('Vehicle id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  if (!(await vehicleRepository.exists(id))) {
    return null;
  }

  const vehicle = normalizeVehicle(payload, id);
  const updatedVehicle = await vehicleRepository.update(id, vehicle);

  if (!updatedVehicle) {
    return null;
  }

  try {
    await publishVehicleEvent({
      eventType: 'vehicule.modifie',
      vehicle: updatedVehicle,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour vehicule.modifie:', error.message);
  }

  return updatedVehicle;
};

const deleteVehicle = async (id) => {
  if (!isUuid(id)) {
    const error = new Error('Vehicle id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const existingVehicle = await vehicleRepository.findById(id);
  if (!existingVehicle) {
    return false;
  }

  const deleted = await vehicleRepository.remove(id);
  if (!deleted) {
    return false;
  }

  try {
    await publishVehicleEvent({
      eventType: 'vehicule.supprime',
      vehicle: existingVehicle,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour vehicule.supprime:', error.message);
  }

  return true;
};

const shouldImmobilizeImmediately = ({ urgencyLevel, scheduledDate, requiresImmediateImmobilization }) => {
  if (requiresImmediateImmobilization) {
    return true;
  }

  if (typeof urgencyLevel === 'string' && urgencyLevel.toUpperCase() === 'HIGH') {
    return true;
  }

  const scheduledAt = new Date(scheduledDate);
  if (Number.isNaN(scheduledAt.getTime())) {
    return true;
  }

  const thresholdDate = new Date(Date.now() + (IMMEDIATE_MAINTENANCE_THRESHOLD_HOURS * 60 * 60 * 1000));
  return scheduledAt <= thresholdDate;
};

const handleMaintenanceDemand = async (event) => {
  const payload = event?.payload || {};
  const {
    maintenanceId,
    vehicleId,
    urgencyLevel,
    scheduledDate,
    reason,
    requiresImmediateImmobilization,
  } = payload;

  if (!maintenanceId || !vehicleId) {
    return;
  }

  const vehicle = await vehicleRepository.findById(vehicleId);

  if (!vehicle) {
    await publishVehicleEvent({
      eventType: 'vehicule.immobilisation_echouee',
      payload: {
        maintenanceId,
        reasonCode: 'VEHICLE_NOT_FOUND_OR_BUSY',
        reasonMessage: 'Véhicule introuvable ou déjà indisponible',
      },
      key: maintenanceId,
      correlationId: event.correlationId || maintenanceId,
      causationId: event.eventId,
      entity: 'vehicule',
    });
    return;
  }

  const immediate = shouldImmobilizeImmediately({
    urgencyLevel,
    scheduledDate,
    requiresImmediateImmobilization,
  });

  if (immediate) {
    if (vehicle.statut !== 'AVAILABLE') {
      await publishVehicleEvent({
        eventType: 'vehicule.immobilisation_echouee',
        payload: {
          maintenanceId,
          reasonCode: 'VEHICLE_NOT_FOUND_OR_BUSY',
          reasonMessage: 'Véhicule introuvable ou déjà indisponible',
        },
        key: maintenanceId,
        correlationId: event.correlationId || maintenanceId,
        causationId: event.eventId,
        entity: 'vehicule',
      });
      return;
    }

    const updatedVehicle = await vehicleRepository.updateStatus(vehicleId, 'MAINTENANCE');

    await publishVehicleEvent({
      eventType: 'vehicule.immobilise',
      payload: {
        maintenanceId,
        vehicleId,
        immobilizationStartedAt: new Date().toISOString(),
      },
      key: maintenanceId,
      correlationId: event.correlationId || maintenanceId,
      causationId: event.eventId,
      entity: 'vehicule',
    });

    if (updatedVehicle) {
      await publishVehicleEvent({
        eventType: 'vehicule.modifie',
        payload: {
          vehicleId: updatedVehicle.id,
          changes: {
            statut: updatedVehicle.statut,
          },
        },
        key: updatedVehicle.id,
        correlationId: event.correlationId || maintenanceId,
        causationId: event.eventId,
        entity: 'vehicule',
      });
    }

    return;
  }

  await publishVehicleEvent({
    eventType: 'vehicule.maintenance_planifiee_sans_immobilisation',
    payload: {
      maintenanceId,
      vehicleId,
      scheduledDate,
      reason: reason || 'Maintenance planifiée sans immobilisation immédiate',
    },
    key: maintenanceId,
    correlationId: event.correlationId || maintenanceId,
    causationId: event.eventId,
    entity: 'vehicule',
  });
};

const handleAssignmentDemand = async (event) => {
  const payload = event?.payload || {};
  const {
    assignmentId,
    vehicleId,
  } = payload;

  if (!assignmentId || !vehicleId) {
    return;
  }

  const vehicle = await vehicleRepository.findById(vehicleId);

  if (!vehicle) {
    await publishVehicleEvent({
      eventType: 'vehicule.affectation_refusee',
      payload: {
        assignmentId,
        vehicleId,
        reasonCode: 'VEHICLE_NOT_FOUND',
        reasonMessage: 'Véhicule introuvable',
      },
      key: assignmentId,
      correlationId: event.correlationId || assignmentId,
      causationId: event.eventId,
      entity: 'affectation',
    });
    return;
  }

  if (vehicle.statut !== 'AVAILABLE') {
    await publishVehicleEvent({
      eventType: 'vehicule.affectation_refusee',
      payload: {
        assignmentId,
        vehicleId,
        reasonCode: 'VEHICLE_NOT_AVAILABLE',
        reasonMessage: 'Véhicule indisponible',
      },
      key: assignmentId,
      correlationId: event.correlationId || assignmentId,
      causationId: event.eventId,
      entity: 'affectation',
    });
    return;
  }

  const updatedVehicle = await vehicleRepository.updateStatus(vehicleId, 'IN_USE');

  await publishVehicleEvent({
    eventType: 'vehicule.affectation_acceptee',
    payload: {
      assignmentId,
      vehicleId,
    },
    key: assignmentId,
    correlationId: event.correlationId || assignmentId,
    causationId: event.eventId,
    entity: 'affectation',
  });

  if (updatedVehicle) {
    await publishVehicleEvent({
      eventType: 'vehicule.modifie',
      payload: {
        vehicleId: updatedVehicle.id,
        changes: {
          statut: updatedVehicle.statut,
        },
      },
      key: updatedVehicle.id,
      correlationId: event.correlationId || assignmentId,
      causationId: event.eventId,
      entity: 'vehicule',
    });
  }
};

module.exports = {
  listVehicles,
  getVehicleById,
  createVehicle,
  updateVehicle,
  deleteVehicle,
  handleMaintenanceDemand,
  handleAssignmentDemand,
};