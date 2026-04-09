const { QrOffer, customerDetailQR } = require('../../models');

// CREATE Offer
exports.createOffer = async (req, res) => {
  try {
    const { offer_code, offer_type, offer_value } = req.body;

    if (!["percent", "cash"].includes(offer_type)) {
      return res.status(400).json({ message: "Invalid offer_type. Must be 'percent' or 'cash'." });
    }

    const existing = await QrOffer.findOne({ where: { offer_code } });
    if (existing) {
      return res.status(400).json({ message: "Offer code already exists." });
    }

    const offer = await QrOffer.create({ offer_code, offer_type, offer_value });
    res.status(201).json(offer);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// GET all offers
exports.getAllOffers = async (req, res) => {
  console.log("Fetching all offers");
  try {
    const offers = await QrOffer.findAll();
    res.status(200).json(offers);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// For billing time — get offer by phone number
exports.getOfferByPhone = async (req, res) => {
  try {
    const { phone } = req.params;

    const customer = await customerDetailQR.findOne({
      where: { phone },
      include: [{ model: Offer, as: 'offer' }]
    });

    if (!customer) {
      return res.status(404).json({ message: "No customer found" });
    }

    res.status(200).json(customer.offer);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};


// GET offer by offer_code
exports.getOfferByCode = async (req, res) => {
  console.log("Fetching offer by code:", req.params.offerCode);
  try {
    const offerCode = req.params.offerCode;
    console.log(req.params.offerCode);
    const offer = await QrOffer.findOne({ where: { offer_code: offerCode } });

    if (!offer) {
      return res.status(404).json({ error: 'Offer not found' });
    }

    res.json(offer);
  } catch (error) {
    console.error('Error fetching offer by code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// UPDATE offer (optional)
exports.updateOffer = async (req, res) => {
  try {
    const { id } = req.params;
    const { offer_type, offer_value } = req.body;

    const [updated] = await QrOffer.update(
      { offer_type, offer_value },
      { where: { id } }
    );

    if (updated) {
      const updatedOffer = await QrOffer.findOne({ where: { id } });
      return res.status(200).json(updatedOffer);
    }

    return res.status(404).json({ message: "Offer not found" });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
};

// DELETE offer (optional)
exports.deleteOffer = async (req, res) => {
  try {
    const { id } = req.params;

    const deleted = await QrOffer.destroy({ where: { id } });

    if (deleted) {
      return res.status(200).json({ message: "Offer deleted successfully" });
    }

    return res.status(404).json({ message: "Offer not found" });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
};