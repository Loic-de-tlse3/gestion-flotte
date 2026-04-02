const { randomUUID } = require('crypto');
const conducteurRepository = require('../repositories/conducteurRepository');
const assignmentRepository = require('../repositories/assignmentRepository');
const { publishConducteurEvent } = require('../kafka/producer');

const isUuid = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const normalizeConducteur = (payload, id) => ({
  id,
  keycloakId: payload.keycloakId.trim(),
  numeroPermis: payload.numeroPermis.trim(),
  nom: payload.nom.trim(),
  prenom: payload.prenom.trim(),
  email: payload.email.trim(),
  telephone: payload.telephone.trim(),
  statutPermis: payload.statutPermis,
  categoriePermis: typeof payload.categoriePermis === 'string' ? payload.categoriePermis.trim() : null,
});

const listConducteurs = () => conducteurRepository.findAll();

const getConducteurById = (id) => conducteurRepository.findById(id);

const createConducteur = async (payload) => {
  const requestedId = typeof payload.id === 'string' ? payload.id.trim() : '';
  const id = requestedId || randomUUID();

  if (!isUuid(id)) {
    const error = new Error('Conducteur id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  if (await conducteurRepository.exists(id)) {
    const error = new Error('Conducteur id already exists');
    error.status = 409;
    throw error;
  }

  const existingByTelephone = await conducteurRepository.findByTelephone(payload.telephone.trim());
  if (existingByTelephone) {
    const error = new Error('Driver telephone already exists');
    error.status = 409;
    throw error;
  }

  const conducteur = normalizeConducteur(payload, id);
  const createdConducteur = await conducteurRepository.create(conducteur);

  try {
    await publishConducteurEvent({
        eventType: 'conducteur.cree',
        conducteur: createdConducteur,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour conducteur.cree:', error.message);
  }

  return createdConducteur;
};

const updateConducteur = async (id, payload) => {
  if (!isUuid(id)) {
    const error = new Error('Conducteur id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  if (!(await conducteurRepository.exists(id))) {
    return null;
  }

  const existingByTelephone = await conducteurRepository.findByTelephone(payload.telephone.trim());
  if (existingByTelephone && existingByTelephone.id !== id) {
    const error = new Error('Driver telephone already exists');
    error.status = 409;
    throw error;
  }

  const conducteur = normalizeConducteur(payload, id);
  const updatedConducteur = await conducteurRepository.update(id, conducteur);

  if (!updatedConducteur) {
    return null;
  }

  try {
    await publishConducteurEvent({
      eventType: 'conducteur.modifie',
      conducteur: updatedConducteur,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour conducteur.modifie:', error.message);
  }

  return updatedConducteur;
};

const deleteConducteur = async (id) => {
  if (!isUuid(id)) {
    const error = new Error('Conducteur id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const existingConducteur = await conducteurRepository.findById(id);
  if (!existingConducteur) {
    return false;
  }

  const deleted = await conducteurRepository.remove(id);
  if (!deleted) {
    return false;
  }

  try {
    await publishConducteurEvent({
      eventType: 'conducteur.supprime',
      conducteur: existingConducteur,
    });
  } catch (error) {
    console.error('[Kafka] Publication échouée pour conducteur.supprime:', error.message);
  }

  return true;
};

const listAssignmentsByDriver = async (driverId, { activeOnly = false } = {}) => {
  if (!isUuid(driverId)) {
    const error = new Error('Conducteur id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  if (!(await conducteurRepository.exists(driverId))) {
    return null;
  }

  return assignmentRepository.findByDriverId(driverId, { activeOnly });
};

const createAssignmentForDriver = async (driverId, payload) => {
  if (!isUuid(driverId)) {
    const error = new Error('Conducteur id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const driver = await conducteurRepository.findById(driverId);
  if (!driver) {
    return null;
  }

  if (!driver.statutPermis) {
    const error = new Error('Driver license is not valid for assignment');
    error.status = 409;
    throw error;
  }

  const vehicleId = payload.vehicleId.trim();
  if (!isUuid(vehicleId)) {
    const error = new Error('vehicleId must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const activeAssignmentForDriver = await assignmentRepository.findActiveByDriverId(driverId);
  if (activeAssignmentForDriver) {
    const error = new Error('Driver already has an active assignment');
    error.status = 409;
    throw error;
  }

  const activeAssignmentForVehicle = await assignmentRepository.findActiveByVehicleId(vehicleId);
  if (activeAssignmentForVehicle) {
    const error = new Error('Vehicle already has an active assignment');
    error.status = 409;
    throw error;
  }

  const requestedId = typeof payload.id === 'string' ? payload.id.trim() : '';
  const assignmentId = requestedId || randomUUID();

  if (!isUuid(assignmentId)) {
    const error = new Error('Assignment id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const dateDebut = payload.dateDebut ? new Date(payload.dateDebut) : new Date();
  if (Number.isNaN(dateDebut.getTime())) {
    const error = new Error('dateDebut must be a valid date');
    error.status = 400;
    throw error;
  }

  const assignment = {
    id: assignmentId,
    driverId,
    vehicleId,
    dateDebut: dateDebut.toISOString(),
    dateFin: null,
    motif: typeof payload.motif === 'string' ? payload.motif.trim() : null,
  };

  const createdAssignment = await assignmentRepository.create(assignment);

  await publishConducteurEvent({
    eventType: 'conducteur.affectation_demandee',
    payload: {
      assignmentId: createdAssignment.id,
      driverId: createdAssignment.driverId,
      vehicleId: createdAssignment.vehicleId,
      requestedAt: new Date().toISOString(),
    },
    key: createdAssignment.id,
    correlationId: createdAssignment.id,
    entity: 'affectation',
  });

  return createdAssignment;
};

const closeAssignment = async (assignmentId, payload) => {
  if (!isUuid(assignmentId)) {
    const error = new Error('Assignment id must be a valid UUID');
    error.status = 400;
    throw error;
  }

  const existingAssignment = await assignmentRepository.findById(assignmentId);
  if (!existingAssignment) {
    return null;
  }

  if (existingAssignment.dateFin) {
    const error = new Error('Assignment is already closed');
    error.status = 409;
    throw error;
  }

  const dateFin = payload.dateFin ? new Date(payload.dateFin) : new Date();
  if (Number.isNaN(dateFin.getTime())) {
    const error = new Error('dateFin must be a valid date');
    error.status = 400;
    throw error;
  }

  const dateDebut = new Date(existingAssignment.dateDebut);
  if (dateFin <= dateDebut) {
    const error = new Error('dateFin must be greater than assignment start date');
    error.status = 400;
    throw error;
  }

  return assignmentRepository.close(assignmentId, dateFin.toISOString());
};

const handleVehicleAssignmentEvent = async (event) => {
  const assignmentId = event?.payload?.assignmentId;
  if (!assignmentId || !isUuid(assignmentId)) {
    return null;
  }

  const assignment = await assignmentRepository.findById(assignmentId);
  if (!assignment) {
    return null;
  }

  if (event.eventType === 'vehicule.affectation_acceptee') {
    await publishConducteurEvent({
      eventType: 'conducteur.assigne',
      payload: {
        assignmentId,
        driverId: assignment.driverId,
        vehicleId: assignment.vehicleId,
        status: 'ASSIGNED',
      },
      key: assignmentId,
      correlationId: event.correlationId || assignmentId,
      causationId: event.eventId,
      entity: 'affectation',
    });

    return assignment;
  }

  if (event.eventType === 'vehicule.affectation_refusee') {
    if (!assignment.dateFin) {
      const assignmentStartAt = new Date(assignment.dateDebut).getTime();
      const cancellationDate = new Date(Math.max(Date.now(), assignmentStartAt + 1000));
      await assignmentRepository.close(assignmentId, cancellationDate.toISOString());
    }

    await publishConducteurEvent({
      eventType: 'conducteur.affectation_annulee',
      payload: {
        assignmentId,
        driverId: assignment.driverId,
        vehicleId: assignment.vehicleId,
        status: 'CANCELLED',
        reasonCode: event.payload?.reasonCode || 'VEHICLE_NOT_AVAILABLE',
        reasonMessage: event.payload?.reasonMessage || 'Affectation refusée par le service véhicule',
      },
      key: assignmentId,
      correlationId: event.correlationId || assignmentId,
      causationId: event.eventId,
      entity: 'affectation',
    });

    return assignment;
  }

  return null;
};

module.exports = {
  listConducteurs,
  getConducteurById,
  createConducteur,
  updateConducteur,
  deleteConducteur,
  listAssignmentsByDriver,
  createAssignmentForDriver,
  closeAssignment,
  handleVehicleAssignmentEvent,
};
