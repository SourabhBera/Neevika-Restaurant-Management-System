const { Ingredient } = require('../../models');

// Get all ingredients
const getIngredients = async (req, res) => {
  try {
    const ingredients = await Ingredient.findAll();
    res.json(ingredients);
  } catch (error) {
    console.error('Error fetching ingredients:', error);
    res.status(500).json({ message: 'Error fetching ingredients', error: error.message });
  }
};

// Get ingredient by ID
const getIngredientById = async (req, res) => {
  try {
    const ingredient = await Ingredient.findByPk(req.params.id);
    if (!ingredient) {
      return res.status(404).json({ message: 'Ingredient not found' });
    }
    res.json(ingredient);
  } catch (error) {
    console.error('Error fetching ingredient by ID:', error);
    res.status(500).json({ message: 'Error fetching ingredient', error: error.message });
  }
};

// Create new ingredient
const createIngredient = async (req, res) => {
  try {
    const { itemName, description } = req.body;
    const ingredient = await Ingredient.create({ itemName, description });
    res.status(201).json(ingredient);
  } catch (error) {
    console.error('Error creating ingredient:', error);
    res.status(500).json({ message: 'Error creating ingredient', error: error.message });
  }
};

// Update ingredient
const updateIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const { itemName, description } = req.body;

    const ingredient = await Ingredient.findByPk(id);
    if (!ingredient) {
      return res.status(404).json({ message: 'Ingredient not found' });
    }

    await ingredient.update({ itemName, description });
    res.json(ingredient);
  } catch (error) {
    console.error('Error updating ingredient:', error);
    res.status(500).json({ message: 'Error updating ingredient', error: error.message });
  }
};

// Delete ingredient
const deleteIngredient = async (req, res) => {
  try {
    const { id } = req.params;
    const ingredient = await Ingredient.findByPk(id);
    if (!ingredient) {
      return res.status(404).json({ message: 'Ingredient not found' });
    }

    await ingredient.destroy();
    res.json({ message: 'Ingredient deleted successfully!' });
  } catch (error) {
    console.error('Error deleting ingredient:', error);
    res.status(500).json({ message: 'Error deleting ingredient', error: error.message });
  }
};

module.exports = {
  getIngredients,
  getIngredientById,
  createIngredient,
  updateIngredient,
  deleteIngredient,
};
