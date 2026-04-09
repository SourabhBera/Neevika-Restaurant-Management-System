// controllers/vendorController.js
const { Vendor, User, PurchaseHistory, DrinksPurchaseHistory } = require('../../models');
const logger = require('../../configs/logger');

// Create a new vendor
const createVendor = async (req, res) => {
  try {
    console.log(req.body);
    const vendor = await Vendor.create(req.body);

    res.status(201).json({ message: 'Vendor created successfully', vendor });
  } catch (error) {
    logger.error(`Error creating vendor: ${error.message}`);
    res.status(500).json({ message: 'Error creating vendor', error: error.message });
  }
};

// Get all vendors
const getAllVendors = async (req, res) => {
  try {
    const vendors = await Vendor.findAll({ include: [{ model: User, as: 'user' }] });
    res.status(200).json(vendors);
  } catch (error) {
    logger.error(`Error fetching vendors: ${error.message}`);
    res.status(500).json({ message: 'Error fetching vendors', error: error.message });
  }
};


// Get vendor by ID 
const getVendorById = async (req, res) => {
  const { id } = req.params;

  try {
    // Fetch the vendor with associated user
    const vendor = await Vendor.findByPk(id, {
      include: [{ model: User, as: 'user' }]
    });

    if (!vendor) {
      return res.status(404).json({ message: 'Vendor not found' });
    }

    // Fetch food purchase history
    const purchaseHistories = await PurchaseHistory.findAll({
      where: { vendor_id: id }
    });

    // Fetch drinks purchase history
    const drinksPurchaseHistories = await DrinksPurchaseHistory.findAll({
      where: { vendor_id: id }
    });

    // Group food purchases
    const groupedPurchaseHistories = {
      pending: [],
      complete: []
    };

    purchaseHistories.forEach(history => {
      const isPending = history.delivery_status === 'pending';

      if (isPending) {
        groupedPurchaseHistories.pending.push(history);
      } else {
        groupedPurchaseHistories.complete.push(history);
      }
    });

    // Group drinks purchases
    const groupedDrinksPurchaseHistories = {
      pending: [],
      complete: []
    };

    drinksPurchaseHistories.forEach(history => {
      const isPending = history.delivery_status === 'pending';

      if (isPending) {
        groupedDrinksPurchaseHistories.pending.push(history);
      } else {
        groupedDrinksPurchaseHistories.complete.push(history);
      }
    });

    // Final response
    res.status(200).json({
      vendor,
      purchaseHistories: groupedPurchaseHistories,
      drinksPurchaseHistories: groupedDrinksPurchaseHistories
    });

  } catch (error) {
    logger.error(`Error fetching vendor or purchase history: ${error.message}`);
    res.status(500).json({ message: 'Error fetching vendor', error: error.message });
  }
};



// Update vendor
const updateVendor = async (req, res) => {
  const { id } = req.params;
  try {
    const vendor = await Vendor.findByPk(id);
    if (!vendor) {
      return res.status(404).json({ message: 'Vendor not found' });
    }
    await vendor.update(req.body);
    res.status(200).json({ message: 'Vendor updated successfully', vendor });
  } catch (error) {
    logger.error(`Error updating vendor: ${error.message}`);
    res.status(500).json({ message: 'Error updating vendor', error: error.message });
  }
};

// Delete vendor
const deleteVendor = async (req, res) => {
  const { id } = req.params;
  try {
    const vendor = await Vendor.findByPk(id);
    if (!vendor) {
      return res.status(404).json({ message: 'Vendor not found' });
    }
    await vendor.destroy();
    res.status(200).json({ message: 'Vendor deleted successfully' });
  } catch (error) {
    logger.error(`Error deleting vendor: ${error.message}`);
    res.status(500).json({ message: 'Error deleting vendor', error: error.message });
  }
};


module.exports = {
    createVendor,
    getAllVendors,
    getVendorById,
    updateVendor,
    deleteVendor,
  };
  