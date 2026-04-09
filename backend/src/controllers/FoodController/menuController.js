const { Category, Menu } = require("../../models");
const { sequelize } = require("../../models");
const { Op } = require('sequelize');
const NodeCache = require("node-cache");

// Initialize caches with different TTLs
const categoryCache = new NodeCache({ stdTTL: 3600 }); // 1 hour for categories
// ✅ Reduced from 60s → 10s. Flutter applies optimistic updates instantly;
//    this just keeps other devices/sessions in sync within 10 seconds.
const menuCache = new NodeCache({ stdTTL: 10 });

// Create Menu Item
const createMenuItem = async (req, res) => {
  try {
    const {
      name,
      description,
      price,
      veg,
      categoryId,
      isOffer,
      offerPrice,
      waiterCommission,
      commissionType,
    } = req.body;
    console.log(req.body);

    const category = await Category.findByPk(categoryId);
    if (!category) {
      return res.status(404).json({ error: "Category not found" });
    }

    if (isOffer) {
      if (!offerPrice || offerPrice <= 0) {
        return res
          .status(400)
          .json({ error: "Offer price must be provided and greater than 0" });
      }
      if (!waiterCommission || waiterCommission <= 0) {
        return res.status(400).json({
          error: "Waiter commission must be provided and greater than 0",
        });
      }
      if (!commissionType || !["flat", "percentage"].includes(commissionType)) {
        return res.status(400).json({
          error: "Invalid commission type, must be flat or percentage",
        });
      }
    }

    const menu = await Menu.create({
      name,
      description,
      price,
      veg,
      categoryId,
      isOffer: isOffer || false,
      offerPrice: isOffer ? offerPrice : null,
      waiterCommission: isOffer ? waiterCommission : null,
      commissionType: isOffer ? commissionType : null,
    });

    // ✅ Flush so next fetch reflects new item immediately
    menuCache.flushAll();

    res.status(201).json(menu);
  } catch (error) {
    console.error("Error creating menu:", error);
    res.status(500).json({ error: "Error creating menu" });
  }
};

const getMenuItems = async (req, res) => {
  try {
    res.set('Cache-Control', 'public, max-age=10');

    const { search, category, vegOnly, limit = 100, offset = 0 } = req.query;

    const normalizedSearch = (search || '').trim().toLowerCase();
    const normalizedCategory = (category || '').toString();
    const normalizedVeg = (vegOnly || '').toString();

    const cacheKey = `menu_search:${normalizedSearch}_cat:${normalizedCategory}_veg:${normalizedVeg}_lim:${limit}_off:${offset}`;
    const cached = menuCache.get(cacheKey);
    if (cached) {
      console.log(`[MENU CACHE] hit key=${cacheKey}`);
      return res.status(200).json(cached);
    }
    console.log(`[MENU CACHE] miss key=${cacheKey}`);

    const where = {};

    if (normalizedSearch) {
      where[Op.and] = [
        {
          [Op.or]: [
            sequelize.where(
              sequelize.fn('LOWER', sequelize.col('Menu.name')),
              { [Op.like]: `%${normalizedSearch}%` }
            ),
            sequelize.where(
              sequelize.fn('LOWER', sequelize.col('Menu.description')),
              { [Op.like]: `%${normalizedSearch}%` }
            ),
          ]
        }
      ];
    }

    if (category && category !== 'All') {
      if (category === 'Offer') {
        where.isOffer = true;
      } else if (category === 'Urgent Sale') {
        where.isUrgent = true;
      } else {
        const maybeId = parseInt(category, 10);
        if (!Number.isNaN(maybeId)) {
          where.categoryId = maybeId;
        } else {
          const foundCat = await Category.findOne({
            where: sequelize.where(
              sequelize.fn('LOWER', sequelize.col('name')),
              category.toString().toLowerCase()
            ),
            attributes: ['id'],
            raw: true
          });
          if (foundCat) {
            where.categoryId = foundCat.id;
          } else {
            console.log(`[MENU] category name not found: "${category}"`);
            where.categoryId = -999999;
          }
        }
      }
    }

    if (vegOnly === 'true') {
      where.veg = true;
    }

    console.log('[MENU] query where:', JSON.stringify(where));

    const menuItems = await Menu.findAll({
      where,
      attributes: [
        'id', 'name', 'description', 'price', 'veg',
        'categoryId', 'isOffer', 'isUrgent', 'offerPrice',
        'waiterCommission', 'commissionType'
      ],
      order: [
        ['isUrgent', 'DESC'],
        ['id', 'ASC']
      ],
      limit: parseInt(limit, 10),
      offset: parseInt(offset, 10),
      raw: true
    });

    menuCache.set(cacheKey, menuItems);
    res.status(200).json(menuItems);
  } catch (error) {
    console.error("Error fetching menu items:", error);
    res.status(500).json({ message: "Error fetching menu items", error: error.message });
  }
};

// Get Menu Item by ID
const getMenuItemById = async (req, res) => {
  try {
    const menuItem = await Menu.findByPk(req.params.id);
    if (!menuItem) {
      return res.status(404).json({ message: "Menu item not found" });
    }
    res.status(200).json(menuItem);
  } catch (error) {
    console.error("Error fetching menu item:", error);
    res.status(500).json({ message: "Error fetching menu item", error });
  }
};

const updateMenuItem = async (req, res) => {
  try {
    const { id } = req.params;

    const {
      name,
      description,
      price,
      veg,
      categoryId,
      isOffer,
      isUrgent = false,
      offerPrice,
      waiterCommission,
      commissionType,
    } = req.body;

    const menu = await Menu.findByPk(id);

    if (!menu) {
      return res.status(404).json({ error: "Menu not found" });
    }

    console.log("isUrgent: ", isUrgent);

    let finalOfferPrice = offerPrice;

    if (isOffer === true) {
      if (!finalOfferPrice || finalOfferPrice === 0) {
        finalOfferPrice = price || menu.price;
      }

      if (!waiterCommission || waiterCommission <= 0) {
        return res.status(400).json({
          error: "Waiter commission must be provided and greater than 0",
        });
      }

      if (!commissionType || !["flat", "percentage"].includes(commissionType)) {
        return res.status(400).json({
          error: "Invalid commission type, must be flat or percentage",
        });
      }
    }

    await menu.update({
      name,
      description,
      price,
      veg,
      isUrgent,
      categoryId,
      isOffer: typeof isOffer !== "undefined" ? isOffer : menu.isOffer,

      offerPrice:
        isOffer === true
          ? finalOfferPrice
          : isOffer === false
          ? null
          : menu.offerPrice,

      waiterCommission:
        isOffer === true
          ? waiterCommission
          : isOffer === false
          ? null
          : menu.waiterCommission,

      commissionType:
        isOffer === true
          ? commissionType
          : isOffer === false
          ? null
          : menu.commissionType,
    });

    // ✅ Flush ALL cache keys — next silent background fetch gets fresh data
    menuCache.flushAll();

    res.status(200).json(menu);
  } catch (error) {
    console.error("Error updating menu:", error);
    res.status(500).json({ error: "Error updating menu" });
  }
};

// Delete Menu Item
const deleteMenuItem = async (req, res) => {
  try {
    const menuItem = await Menu.findByPk(req.params.id);
    if (!menuItem) {
      return res.status(404).json({ message: "Menu item not found" });
    }
    await menuItem.destroy();
    menuCache.flushAll();
    res.status(200).json({ message: "Menu item deleted successfully" });
  } catch (error) {
    console.error("Error deleting menu item:", error);
    res.status(500).json({ message: "Error deleting menu item", error });
  }
};

module.exports = {
  createMenuItem,
  getMenuItems,
  getMenuItemById,
  updateMenuItem,
  deleteMenuItem,
};