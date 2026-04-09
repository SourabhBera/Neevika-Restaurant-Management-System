const express = require('express');
const router = express.Router();
const ingredientController = require('../../controllers/FoodController/ingredientController');

router.get('/', ingredientController.getIngredients);
router.get('/:id', ingredientController.getIngredientById);
router.post('/', ingredientController.createIngredient);
router.put('/:id', ingredientController.updateIngredient);
router.delete('/:id', ingredientController.deleteIngredient);

module.exports = router;
