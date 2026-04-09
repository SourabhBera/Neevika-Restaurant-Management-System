const { InventoryCategory } = require('../../models');

// Get all inventory categories
exports.getAllCategories = async (req, res) => {
  try {
    const categories = await InventoryCategory.findAll();
    res.status(200).json(categories);
  } catch (err) {
    console.error('Error fetching categories:', err);
    res.status(500).json({ error: err.message });
  }
};

// Create a new inventory category
exports.createCategory = async (req, res) => {
  try {
    const { categoryName } = req.body;
    if (!categoryName) return res.status(400).json({ error: 'Category name is required.' });

    const category = await InventoryCategory.create({ categoryName });
    res.status(201).json(category);
  } catch (err) {
    console.error('Error creating category:', err);
    res.status(500).json({ error: err.message });
  }
};

// Update an existing inventory category
exports.updateCategory = async (req, res) => {
  try {
    const { categoryName } = req.body;
    if (!categoryName) return res.status(400).json({ error: 'Category name is required.' });

    const category = await InventoryCategory.findByPk(req.params.id);
    if (!category) return res.status(404).json({ error: 'Category not found.' });

    category.categoryName = categoryName;
    await category.save();
    res.status(200).json(category);
  } catch (err) {
    console.error('Error updating category:', err);
    res.status(500).json({ error: err.message });
  }
};
