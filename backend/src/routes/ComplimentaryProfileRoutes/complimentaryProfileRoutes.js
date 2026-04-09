const express = require('express');
const router = express.Router();
const complimentaryProfileController = require('../../controllers/ComplimentaryProfileController/ComplimentaryProfileController');

// CRUD routes
router.post('/', complimentaryProfileController.createProfile);
router.get('/', complimentaryProfileController.getAllProfiles);
router.get('/:id', complimentaryProfileController.getProfileById);
router.put('/:id', complimentaryProfileController.updateProfile);
router.delete('/:id', complimentaryProfileController.deleteProfile);
router.get('/:id/bills', complimentaryProfileController.getBillsByComplimentaryProfile);

module.exports = router;
