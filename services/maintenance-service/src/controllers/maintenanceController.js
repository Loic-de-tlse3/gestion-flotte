const maintenanceService = require('../services/maintenanceService');

const createMaintenance = async (req, res, next) => {
  try {
    const maintenance = await maintenanceService.createMaintenance(req.body);
    res.status(201).json(maintenance);
  } catch (error) {
    next(error);
  }
};

const listMaintenances = async (req, res, next) => {
  try {
    const maintenances = await maintenanceService.listMaintenances();
    res.status(200).json(maintenances);
  } catch (error) {
    next(error);
  }
};

const getMaintenanceById = async (req, res, next) => {
  try {
    const maintenance = await maintenanceService.getMaintenanceById(req.params.id);

    if (!maintenance) {
      return res.status(404).json({ message: 'Maintenance not found' });
    }

    return res.status(200).json(maintenance);
  } catch (error) {
    next(error);
  }
};

module.exports = {
  createMaintenance,
  listMaintenances,
  getMaintenanceById,
};
