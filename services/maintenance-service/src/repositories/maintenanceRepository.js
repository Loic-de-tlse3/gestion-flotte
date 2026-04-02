const maintenances = new Map();

const normalize = (maintenance) => ({
  ...maintenance,
  createdAt: maintenance.createdAt,
  updatedAt: maintenance.updatedAt,
});

const create = async (maintenance) => {
  maintenances.set(maintenance.id, maintenance);
  return normalize(maintenance);
};

const findById = async (id) => {
  const maintenance = maintenances.get(id);
  return maintenance ? normalize(maintenance) : null;
};

const findAll = async () => {
  return Array.from(maintenances.values())
    .sort((first, second) => new Date(second.createdAt) - new Date(first.createdAt))
    .map(normalize);
};

const updateStatus = async (id, status, failureReason = null) => {
  const maintenance = maintenances.get(id);
  if (!maintenance) {
    return null;
  }

  const updated = {
    ...maintenance,
    status,
    failureReason,
    updatedAt: new Date().toISOString(),
  };

  maintenances.set(id, updated);
  return normalize(updated);
};

module.exports = {
  create,
  findById,
  findAll,
  updateStatus,
};
