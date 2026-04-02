const { randomUUID } = require('crypto');
const maintenanceRepository = require('../repositories/maintenanceRepository');
const { publishMaintenanceEvent } = require('../kafka/producer');

const MAINTENANCE_TYPES = ['PREVENTIVE', 'CORRECTIVE', 'URGENT'];
const URGENCY_LEVELS = ['LOW', 'MEDIUM', 'HIGH'];

const isUuid = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const normalizeCreatePayload = (payload) => {
  const requestedId = typeof payload.maintenanceId === 'string' ? payload.maintenanceId.trim() : '';
  const maintenanceId = requestedId || randomUUID();

  if (!isUuid(maintenanceId)) {
    const error = new Error('maintenanceId must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const vehicleId = typeof payload.vehicleId === 'string' ? payload.vehicleId.trim() : '';
  if (!isUuid(vehicleId)) {
    const error = new Error('vehicleId must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const maintenanceType = typeof payload.maintenanceType === 'string' ? payload.maintenanceType.trim().toUpperCase() : 'PREVENTIVE';
  if (!MAINTENANCE_TYPES.includes(maintenanceType)) {
    const error = new Error(`maintenanceType must be one of: ${MAINTENANCE_TYPES.join(', ')}`);
    error.status = 400;
    throw error;
  }

  const reason = typeof payload.reason === 'string' ? payload.reason.trim() : '';
  if (!reason) {
    const error = new Error('reason is required');
    error.status = 400;
    throw error;
  }

  const urgencyLevel = typeof payload.urgencyLevel === 'string' ? payload.urgencyLevel.trim().toUpperCase() : 'LOW';
  if (!URGENCY_LEVELS.includes(urgencyLevel)) {
    const error = new Error(`urgencyLevel must be one of: ${URGENCY_LEVELS.join(', ')}`);
    error.status = 400;
    throw error;
  }

  const scheduledDateRaw = typeof payload.scheduledDate === 'string' ? payload.scheduledDate.trim() : '';
  const scheduledDate = new Date(scheduledDateRaw || Date.now());
  if (Number.isNaN(scheduledDate.getTime())) {
    const error = new Error('scheduledDate must be a valid ISO date');
    error.status = 400;
    throw error;
  }

  const requiresImmediateImmobilization = Boolean(payload.requiresImmediateImmobilization);

  return {
    maintenanceId,
    vehicleId,
    maintenanceType,
    reason,
    urgencyLevel,
    scheduledDate: scheduledDate.toISOString(),
    requiresImmediateImmobilization,
  };
};

const createMaintenance = async (payload) => {
  const normalized = normalizeCreatePayload(payload);
  const now = new Date().toISOString();

  const maintenance = {
    id: normalized.maintenanceId,
    vehicleId: normalized.vehicleId,
    maintenanceType: normalized.maintenanceType,
    reason: normalized.reason,
    urgencyLevel: normalized.urgencyLevel,
    scheduledDate: normalized.scheduledDate,
    requiresImmediateImmobilization: normalized.requiresImmediateImmobilization,
    requestedAt: now,
    status: 'PENDING',
    failureReason: null,
    createdAt: now,
    updatedAt: now,
  };

  const created = await maintenanceRepository.create(maintenance);

  await publishMaintenanceEvent({
    eventType: 'maintenance.demandee',
    payload: {
      maintenanceId: created.id,
      vehicleId: created.vehicleId,
      maintenanceType: created.maintenanceType,
      reason: created.reason,
      scheduledDate: created.scheduledDate,
      urgencyLevel: created.urgencyLevel,
      requiresImmediateImmobilization: created.requiresImmediateImmobilization,
      requestedAt: created.requestedAt,
    },
    key: created.id,
    entity: 'maintenance',
    correlationId: created.id,
  });

  return created;
};

const listMaintenances = () => maintenanceRepository.findAll();

const getMaintenanceById = (maintenanceId) => maintenanceRepository.findById(maintenanceId);

const handleVehicleEvent = async (event) => {
  const maintenanceId = event?.payload?.maintenanceId;
  if (!maintenanceId) {
    return null;
  }

  const maintenance = await maintenanceRepository.findById(maintenanceId);
  if (!maintenance) {
    return null;
  }

  if (
    event.eventType === 'vehicule.immobilise'
    || event.eventType === 'vehicule.maintenance_planifiee_sans_immobilisation'
  ) {
    const updated = await maintenanceRepository.updateStatus(maintenanceId, 'SCHEDULED', null);

    await publishMaintenanceEvent({
      eventType: 'maintenance.planifiee',
      payload: {
        maintenanceId,
        vehicleId: maintenance.vehicleId,
        status: 'SCHEDULED',
      },
      key: maintenanceId,
      entity: 'maintenance',
      correlationId: event.correlationId || maintenanceId,
      causationId: event.eventId,
    });

    return updated;
  }

  if (event.eventType === 'vehicule.immobilisation_echouee') {
    const reasonCode = event.payload.reasonCode || 'IMMOBILIZATION_FAILED';
    const updated = await maintenanceRepository.updateStatus(maintenanceId, 'CANCELLED', reasonCode);

    await publishMaintenanceEvent({
      eventType: 'maintenance.annulee',
      payload: {
        maintenanceId,
        status: 'CANCELLED',
        reasonCode,
      },
      key: maintenanceId,
      entity: 'maintenance',
      correlationId: event.correlationId || maintenanceId,
      causationId: event.eventId,
    });

    return updated;
  }

  return null;
};

module.exports = {
  createMaintenance,
  listMaintenances,
  getMaintenanceById,
  handleVehicleEvent,
};
