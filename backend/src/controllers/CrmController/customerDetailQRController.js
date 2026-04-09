// controllers/customerDetailQRController.js
const { customerDetailQR, QrOffer, Table  } = require('../../models');

exports.createCustomer = async (req, res) => {
  try {
    let {
      phone,
      name,
      gender,
      birthday,
      anniversary,
      offerId,
      offerType,
      offerValue,
      tableId,
    } = req.body;

    anniversary = anniversary === '' ? null : anniversary;
    birthday = birthday === '' ? null : birthday;

    // Validate required fields
    if (!phone || !name) {
      return res.status(400).json({ message: "Phone and name are required." });
    }

    // Convert tableId if sent as string
    if (tableId && typeof tableId === "string") {
      tableId = parseInt(tableId);
    }

    // Check if customer already exists
    const existing = await customerDetailQR.findOne({ where: { phone } });
    if (existing) {
      return res.status(400).json({ message: "Customer already exists with this phone number." });
    }

    // Fetch offer from DB only if offerId exists
    let offerDetail = null;
    if (offerId) {
      offerDetail = await QrOffer.findByPk(offerId);
    }

    // Create customer with fixed offer details
// Create customer with offer details saved
const customer = await customerDetailQR.create({
  phone,
  name,
  gender,
  email: null,
  birthday,
  anniversary,
  address: null,
  offerId: offerId || null,
  offerType: offerType || null,
  offerValue: offerValue || null,
});

console.log("Body:", req.body);

// Apply discount to table
if (tableId) {
  const tableData = await Table.findByPk(tableId);

  if (tableData) {
    const newDiscountVal = Number(offerValue) || 0;

    const existingDiscountVal =
      tableData.lottery_discount_detail?.discount || 0;

    if (newDiscountVal > existingDiscountVal) {
      await Table.update(
        {
          lottery_discount_detail: {
            discount: newDiscountVal,
            type: offerType || "percent",
            offer_code: "QR",
            source: "QR Lottery",
            customer_phone: phone,
            timestamp: new Date(),
          },
        },
        { where: { id: tableId } }
      );
    }

    const updatedTable = await Table.findByPk(tableId);
    console.log("Updated Table:", updatedTable.lottery_discount_detail);
  }
}

     

    res.status(201).json({
      message: "Registered successfully",
      customer,
    });

  } catch (error) {
    console.error("Error creating customer:", error);
    res.status(500).json({ error: error.message });
  }
};




// READ ALL
exports.getAllCustomers = async (req, res) => {
  try {
    const customers = await customerDetailQR.findAll();
    res.status(200).json(customers);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// READ BY PHONE
exports.getCustomerByPhone = async (req, res) => {
  try {
    const { phone } = req.params;
    const customer = await customerDetailQR.findOne({ where: { phone } });
    if (!customer) return res.status(404).json({ message: "Customer not found" });

    res.status(200).json(customer);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};


const moment = require("moment"); // Make sure to install: npm install moment

exports.getMultipleCustomersByPhones = async (req, res) => {
  try {
    const { phones } = req.body;

    // Validate input
    if (!Array.isArray(phones) || phones.length === 0) {
      return res.status(400).json({ message: "Phone numbers array is required" });
    }

    // Query customers and include offer details
    const customers = await customerDetailQR.findAll({
      where: { phone: phones },
      include: [
        {
          model: QrOffer,
          as: "offer",
          attributes: ["offer_code", "offer_type", "offer_value"]
        }
      ]
    });

    if (!customers || customers.length === 0) {
      return res.status(404).json({ message: "No customers found" });
    }

    // Transform response
    const formatted = customers.map(c => {
      let timeAgo = null;

      if (c.createdAt) {
        const now = moment();
        const created = moment(c.createdAt);

        if (now.diff(created, "days") >= 1) {
          timeAgo = `${now.diff(created, "days")} days ago`;
        } else if (now.diff(created, "hours") >= 1) {
          timeAgo = `${now.diff(created, "hours")} hours ago`;
        } else {
          timeAgo = `${now.diff(created, "minutes")} minutes ago`;
        }
      }

      return {
        name: c.name,
        phone_number: c.phone,
        email: c.email,
        offerId: c.offerId,
        offer: c.offer
          ? {
              offer_code: c.offer.offer_code,
              offer_type: c.offer.offer_type,
              offer_value: c.offer.offer_value
            }
          : null,
        createdAgo: timeAgo
      };
    });

    res.status(200).json(formatted);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};


// UPDATE
exports.updateCustomer = async (req, res) => {
  try {
    const { phone } = req.params;
    const [updated] = await customerDetailQR.update(req.body, { where: { phone } });

    if (updated) {
      const updatedCustomer = await customerDetailQR.findOne({ where: { phone } });
      return res.status(200).json(updatedCustomer);
    }

    res.status(404).json({ message: "Customer not found" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// DELETE
exports.deleteCustomer = async (req, res) => {
  try {
    const { phone } = req.params;
    const deleted = await customerDetailQR.destroy({ where: { phone } });

    if (deleted) {
      return res.status(200).json({ message: "Customer deleted successfully" });
    }

    res.status(404).json({ message: "Customer not found" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
