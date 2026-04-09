const express = require('express');
const router = express.Router();
const offerController = require('../../controllers/CrmController/qrOfferController');

router.post('/', offerController.createOffer);
router.get('/', offerController.getAllOffers);
router.get('/by-phone/:phone', offerController.getOfferByPhone);
router.get('/by-code/:offerCode', offerController.getOfferByCode);
router.put('/:id', offerController.updateOffer);
router.delete('/:id', offerController.deleteOffer);

module.exports = router;
