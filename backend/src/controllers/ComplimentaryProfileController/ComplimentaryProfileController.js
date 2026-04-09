const { ComplimentaryProfile, Bill, User, CustomerDetails, Table, Section } = require('../../models');

// ➕ Create new complimentary profile
exports.createProfile = async (req, res) => {
  try {
    const { name, description, icon, color, active } = req.body;

    const profile = await ComplimentaryProfile.create({
      name,
      description,
      icon,
      color,
      active,
    });

    res.status(201).json(profile);
  } catch (error) {
    console.error('Error creating complimentary profile:', error);
    res.status(500).json({ message: 'Server error while creating profile' });
  }
};

// 📋 Get all profiles
exports.getAllProfiles = async (req, res) => {
  try {
    const profiles = await ComplimentaryProfile.findAll({
      order: [['id', 'ASC']],
    });
    res.json(profiles);
  } catch (error) {
    console.error('Error fetching profiles:', error);
    res.status(500).json({ message: 'Server error while fetching profiles' });
  }
};

// 🔍 Get single profile by ID
exports.getProfileById = async (req, res) => {
  try {
    const profile = await ComplimentaryProfile.findByPk(req.params.id);
    if (!profile) return res.status(404).json({ message: 'Profile not found' });
    res.json(profile);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

// ✏️ Update profile
exports.updateProfile = async (req, res) => {
  try {
    const { name, description, icon, color, active } = req.body;
    const profile = await ComplimentaryProfile.findByPk(req.params.id);

    if (!profile) return res.status(404).json({ message: 'Profile not found' });

    await profile.update({ name, description, icon, color, active });
    res.json(profile);
  } catch (error) {
    console.error('Error updating profile:', error);
    res.status(500).json({ message: 'Server error while updating profile' });
  }
};

// 🗑️ Delete profile
exports.deleteProfile = async (req, res) => {
  try {
    const profile = await ComplimentaryProfile.findByPk(req.params.id);
    if (!profile) return res.status(404).json({ message: 'Profile not found' });

    await profile.destroy();
    res.json({ message: 'Profile deleted successfully' });
  } catch (error) {
    console.error('Error deleting profile:', error);
    res.status(500).json({ message: 'Server error while deleting profile' });
  }
};



// 🧾 ✅ NEW: Get all bills under a complimentary_profile_id
exports.getBillsByComplimentaryProfile = async (req, res) => {
  try {
    const { id } = req.params;

    // Check if profile exists
    const profile = await ComplimentaryProfile.findByPk(id);
    if (!profile) {
      return res.status(404).json({ message: "Complimentary profile not found" });
    }

    // Fetch bills linked with this complimentary profile
    const bills = await Bill.findAll({
      where: { complimentary_profile_id: id },
      include: [
        { model: User, as: "waiter", attributes: ["id", "name"] },
        { model: CustomerDetails, as: "customerDetails" },
        {
          model: Table,
          as: "table",
          include: [
            {
              model: Section,
              as: "section",
              attributes: ["id", "name"]
            }
          ]
        },
        { model: ComplimentaryProfile, as: "complimentaryProfile" }
      ],
      order: [["id", "DESC"]],
    });

    res.json({
      profile,
      total_bills: bills.length,
      bills,
    });

  } catch (error) {
    console.error("Error fetching bills for complimentary profile:", error);
    res.status(500).json({ message: "Server error while fetching bills" });
  }
};
