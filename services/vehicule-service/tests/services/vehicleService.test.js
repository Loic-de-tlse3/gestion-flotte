jest.mock('../../src/repositories/vehicleRepository');
jest.mock('../../src/kafka/producer', () => ({
  publishVehicleEvent: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('crypto');

const vehicleService = require('../../src/services/vehicleService');
const vehicleRepository = require('../../src/repositories/vehicleRepository');
const { randomUUID } = require('crypto');

const VALID_UUID = '123e4567-e89b-12d3-a456-426614174000';

const mockVehicle = {
  id: VALID_UUID,
  immatriculation: 'AB-123-CD',
  marque: 'Toyota',
  modele: 'Corolla',
  statut: 'disponible',
};

describe('vehicleService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    randomUUID.mockReturnValue(mockVehicle.id);
    vehicleRepository.findById.mockResolvedValue(mockVehicle);
  });

  describe('listVehicles', () => {
    it('returns list of vehicles', async () => {
      const vehicles = [mockVehicle];
      vehicleRepository.findAll.mockResolvedValue(vehicles);

      const result = await vehicleService.listVehicles();

      expect(vehicleRepository.findAll).toHaveBeenCalledTimes(1);
      expect(result).toEqual(vehicles);
    });
  });

  describe('getVehicleById', () => {
    it('returns vehicle by id', async () => {
      vehicleRepository.findById.mockResolvedValue(mockVehicle);

      const result = await vehicleService.getVehicleById(mockVehicle.id);

      expect(vehicleRepository.findById).toHaveBeenCalledWith(mockVehicle.id);
      expect(result).toEqual(mockVehicle);
    });

    it('returns null if not found', async () => {
      vehicleRepository.findById.mockResolvedValue(null);

      const result = await vehicleService.getVehicleById(mockVehicle.id);

      expect(result).toBeNull();
    });
  });

  describe('createVehicle', () => {
    const payload = {
      immatriculation: '  AB-123-CD ',
      marque: ' Toyota ',
      modele: ' Corolla ',
      statut: 'disponible',
    };

    it('creates with generated id', async () => {
      vehicleRepository.exists.mockResolvedValue(false);
      vehicleRepository.create.mockResolvedValue(mockVehicle);

      const result = await vehicleService.createVehicle(payload);

      expect(randomUUID).toHaveBeenCalled();
      expect(vehicleRepository.exists).toHaveBeenCalledWith(mockVehicle.id);
      expect(vehicleRepository.create).toHaveBeenCalledWith({
        id: mockVehicle.id,
        immatriculation: 'AB-123-CD',
        marque: 'Toyota',
        modele: 'Corolla',
        statut: 'disponible',
      });
      expect(result).toEqual(mockVehicle);
    });

    it('creates with provided id', async () => {
      const providedId = VALID_UUID;
      const payloadWithId = { ...payload, id: providedId };
      vehicleRepository.exists.mockResolvedValue(false);
      vehicleRepository.create.mockResolvedValue({ ...mockVehicle, id: providedId });

      const result = await vehicleService.createVehicle(payloadWithId);

      expect(randomUUID).not.toHaveBeenCalled();
      expect(result.id).toBe(providedId);
    });

    it('throws 400 for invalid id', async () => {
      const payloadWithInvalidId = { ...payload, id: 'invalid' };

      await expect(vehicleService.createVehicle(payloadWithInvalidId)).rejects.toThrow('Vehicle id must be a valid UUID');

      expect(vehicleRepository.exists).not.toHaveBeenCalled();
    });

    it('throws 409 if id exists', async () => {
      vehicleRepository.exists.mockResolvedValue(true);

      await expect(vehicleService.createVehicle({ ...payload, id: VALID_UUID })).rejects.toThrow('Vehicle id already exists');
    });
  });

  describe('updateVehicle', () => {
    it('updates vehicle', async () => {
      vehicleRepository.exists.mockResolvedValue(true);
      vehicleRepository.update.mockResolvedValue(mockVehicle);

      const payload = {
        immatriculation: ' NEW-PLATE ',
        marque: 'Updated',
        modele: 'Model',
        statut: 'en maintenance',
      };

      const result = await vehicleService.updateVehicle(mockVehicle.id, payload);

      expect(vehicleRepository.exists).toHaveBeenCalledWith(mockVehicle.id);
      expect(vehicleRepository.update).toHaveBeenCalledWith(mockVehicle.id, {
        id: mockVehicle.id,
        immatriculation: 'NEW-PLATE',
        marque: 'Updated',
        modele: 'Model',
        statut: 'en maintenance',
      });
      expect(result).toEqual(mockVehicle);
    });

    it('returns null if not exists', async () => {
      vehicleRepository.exists.mockResolvedValue(false);

      const result = await vehicleService.updateVehicle(mockVehicle.id, {});

      expect(result).toBeNull();
      expect(vehicleRepository.update).not.toHaveBeenCalled();
    });

    it('throws 400 for invalid id', async () => {
      await expect(vehicleService.updateVehicle('invalid', {})).rejects.toThrow('Vehicle id must be a valid UUID');
    });
  });

  describe('deleteVehicle', () => {
    it('deletes vehicle', async () => {
      vehicleRepository.findById.mockResolvedValue(mockVehicle);
      vehicleRepository.remove.mockResolvedValue(true);

      const result = await vehicleService.deleteVehicle(mockVehicle.id);

      expect(result).toBe(true);
      expect(vehicleRepository.findById).toHaveBeenCalledWith(mockVehicle.id);
      expect(vehicleRepository.remove).toHaveBeenCalledWith(mockVehicle.id);
    });

    it('returns false if not exists', async () => {
      vehicleRepository.findById.mockResolvedValue(null);

      const result = await vehicleService.deleteVehicle(mockVehicle.id);

      expect(result).toBe(false);
      expect(vehicleRepository.remove).not.toHaveBeenCalled();
    });

    it('throws 400 for invalid id', async () => {
      await expect(vehicleService.deleteVehicle('invalid')).rejects.toThrow('Vehicle id must be a valid UUID');
    });
  });
});
