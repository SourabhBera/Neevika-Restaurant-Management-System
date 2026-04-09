const express = require('express');
const router = express.Router();
const menuIngredientController = require('../../controllers/FoodController/menuIngredientController');
const {upload, bulkUploadMenuIngredients} = require('../../controllers/FoodController/menuIngredientController');

router.get('/', menuIngredientController.getMenuIngredients);
router.get('/export-excel', menuIngredientController.exportMenuIngredientsToExcel);
router.get('/:id', menuIngredientController.getMenuIngredientById);
router.post('/', menuIngredientController.createMenuIngredient);
router.post('/bulk-upload', upload.single('file'), bulkUploadMenuIngredients);
router.put('/:id', menuIngredientController.updateMenuIngredient);
router.delete('/:id', menuIngredientController.deleteMenuIngredient);

module.exports = router;
