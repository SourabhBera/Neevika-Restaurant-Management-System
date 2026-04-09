const express = require('express');
const router = express.Router();
const {
    getDrinksCategories,
    createDrinksCategory,
    getDrinksCategoryById,
    updateDrinksCategory,
    deleteDrinksCategory,
} = require('../../controllers/DrinksController/drinksCategoryController');

router.get('/', getDrinksCategories);
router.post('/', createDrinksCategory);
router.get('/:id', getDrinksCategoryById);
router.put('/:id', updateDrinksCategory);
router.delete('/:id', deleteDrinksCategory);

module.exports = router;
