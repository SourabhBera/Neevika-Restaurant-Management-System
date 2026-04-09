// Get all categories
const { DrinksCategory } = require('../../models');
const NodeCache = require("node-cache");

// Cache: 1 hour for categories
const drinksCategoryCache = new NodeCache({ stdTTL: 3600 });

// ✅ Get all drink categories
const getDrinksCategories = async (req, res) => {
  try {
    const cached = drinksCategoryCache.get("drinks_categories");
    if (cached) {
      console.log("[DRINKS CATEGORY CACHE] hit");
      return res.status(200).json(cached);
    }

    const categories = await DrinksCategory.findAll({
      attributes: ['id', 'name'], // same as food categories
      raw: true
    });

    drinksCategoryCache.set("drinks_categories", categories);
    console.log("[DRINKS CATEGORY CACHE] miss — cached results");
    res.status(200).json(categories);
  } catch (error) {
    console.error('Error fetching drinks categories:', error);
    res.status(500).json({ message: 'Error fetching drinks categories', error });
  }
};

module.exports = { getDrinksCategories };

// Create a new category
const createDrinksCategory = async (req, res) => {
  try {
    const { name, description } = req.body;
    const category = await DrinksCategory.create({ name, description }); // Missing 'create()' method call
    res.status(201).json(category);
  } catch (error) {
    console.error('Error creating category:', error);
    res.status(500).json({ message: 'Error creating category', error });
  }
};

// Get category by ID
const getDrinksCategoryById = async (req, res) => {
  try {
    const category = await DrinksCategory.findByPk(req.params.id); // Missing 'findByPk()' method call
    if (!category) {
      return res.status(404).json({ message: 'Category not found' });
    }
    res.status(200).json(category);
  } catch (error) {
    console.error('Error fetching category:', error);
    res.status(500).json({ message: 'Error fetching category', error });
  }
};

// Update category
const updateDrinksCategory = async (req, res) => {
  try {
    const category = await DrinksCategory.findByPk(req.params.id); // Missing 'findByPk()' method call
    if (!category) {
      return res.status(404).json({ message: 'Category not found' });
    }
    await category.update(req.body); // Missing 'update()' method and need to call on the 'category' instance
    res.status(200).json(category);
  } catch (error) {
    console.error('Error updating category:', error);
    res.status(500).json({ message: 'Error updating category', error });
  }
};

// Delete category
const deleteDrinksCategory = async (req, res) => {
  try {
    const category = await DrinksCategory.findByPk(req.params.id); // Missing 'findByPk()' method call
    if (!category) {
      return res.status(404).json({ message: 'Category not found' });
    }
    await category.destroy(); // Missing 'destroy()' method and need to call on the 'category' instance
    res.status(204).json({ message: 'Category deleted successfully' });
  } catch (error) {
    console.error('Error deleting category:', error);
    res.status(500).json({ message: 'Error deleting category', error });
  }
};

module.exports = {
  getDrinksCategories,
  createDrinksCategory,
  getDrinksCategoryById,
  updateDrinksCategory,
  deleteDrinksCategory,
};
