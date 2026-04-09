const {
  DrinksMenu,
  DrinksCategory,
  User,
  DrinksMenuIngredient,
  DrinksInventory,
  DrinksKitchenInventory,
} = require("../../models");
const { createLog } = require("../LogsController/logsController");
const { sequelize } = require("../../models");
const { Op } = require("sequelize");
const NodeCache = require("node-cache");

// Reduced TTL to 10s so background re-syncs pick up changes quickly.
// The optimistic update in Flutter gives instant feedback; this just keeps
// things consistent for other devices/sessions.
const drinksCache = new NodeCache({ stdTTL: 10 });

// Get all drinks menus
const getDrinksMenus = async (req, res) => {
  try {
    res.set("Cache-Control", "public, max-age=10");

    const { search, category, limit = 100, offset = 0 } = req.query;

    const normalizedSearch = (search || "").trim().toLowerCase();
    const normalizedCategory = (category || "").toString();

    const cacheKey = `drinks_search:${normalizedSearch}_cat:${normalizedCategory}_lim:${limit}_off:${offset}`;
    const cached = drinksCache.get(cacheKey);
    if (cached) {
      console.log(`[DRINKS CACHE] hit key=${cacheKey}`);
      return res.status(200).json(cached);
    }
    console.log(`[DRINKS CACHE] miss key=${cacheKey}`);

    const where = {};

    // Search by name
    if (normalizedSearch) {
      where[Op.and] = [
        sequelize.where(
          sequelize.fn("LOWER", sequelize.col("name")),
          { [Op.like]: `%${normalizedSearch}%` }
        ),
      ];
    }

    // Category handling (id or name)
    if (category && category !== "All") {
      const maybeId = parseInt(category, 10);
      if (!Number.isNaN(maybeId)) {
        where.drinksCategoryId = maybeId;
      } else {
        const foundCat = await DrinksCategory.findOne({
          where: sequelize.where(
            sequelize.fn("LOWER", sequelize.col("name")),
            category.toString().toLowerCase()
          ),
          attributes: ["id"],
          raw: true,
        });
        if (foundCat) {
          where.drinksCategoryId = foundCat.id;
        } else {
          console.log(`[DRINKS] category name not found: "${category}"`);
          where.drinksCategoryId = -999999;
        }
      }
    }

    console.log("[DRINKS] query where:", JSON.stringify(where));

    const drinksItems = await DrinksMenu.findAll({
      where,
      // ✅ Only fields that actually exist in the DrinksMenu model.
      // 'veg' and 'stockAvailable' are NOT in the model — do not add them.
      attributes: [
        "id",
        "name",
        "price",
        "drinksCategoryId",
        "isOffer",
        "isUrgent",
        "isOutOfStock",
        "offerPrice",
        "waiterCommission",
        "commissionType",
        "applyVAT",
      ],
      order: [
        ["isUrgent", "DESC"],
        ["id", "ASC"],
      ],
      limit: parseInt(limit, 10),
      offset: parseInt(offset, 10),
      raw: true,
    });

    drinksCache.set(cacheKey, drinksItems);
    res.status(200).json(drinksItems);
  } catch (error) {
    console.error("Error fetching drinks menu:", error);
    res
      .status(500)
      .json({ message: "Error fetching drinks menu", error: error.message });
  }
};

// Create a new drink menu item
const createDrinksMenu = async (req, res) => {
  try {
    const {
      name,
      price,
      drinksCategoryId,
      isOffer,
      offerPrice,
      waiterCommission,
      commissionType,
    } = req.body;

    const category = await DrinksCategory.findByPk(drinksCategoryId);
    if (!category) {
      return res.status(404).json({ message: "Category not found" });
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

    const newDrinkMenu = await DrinksMenu.create({
      name,
      price,
      drinksCategoryId,
      isOffer: isOffer || false,
      offerPrice: isOffer ? offerPrice : null,
      waiterCommission: isOffer ? waiterCommission : null,
      commissionType: isOffer ? commissionType : null,
    });

    // Flush cache so next fetch reflects the new item immediately
    drinksCache.flushAll();

    res.status(201).json(newDrinkMenu);
  } catch (error) {
    console.error("Error creating drinks menu:", error);
    res.status(500).json({ message: "Error creating drinks menu", error });
  }
};

// Get a drink menu by ID
const getDrinksMenuById = async (req, res) => {
  try {
    const drinksMenu = await DrinksMenu.findByPk(req.params.id, {
      include: [{ model: DrinksCategory, as: "category" }],
    });

    if (!drinksMenu) {
      return res.status(404).json({ message: "Drinks menu not found" });
    }

    // ✅ Fixed: was referencing undefined `menuCache` — now uses `drinksCache`
    drinksCache.flushAll();

    res.status(200).json(drinksMenu);
  } catch (error) {
    console.error("Error fetching drinks menu:", error);
    res.status(500).json({ message: "Error fetching drinks menu", error });
  }
};

// Update a drink menu item
const updateDrinksMenu = async (req, res) => {
  try {
    const drinksMenu = await DrinksMenu.findByPk(req.params.id);

    const {
      name,
      price,
      drinksCategoryId,
      isOffer,
      isUrgent = false,
      offerPrice,
      isOutOfStock = false,
      waiterCommission,
      commissionType,
    } = req.body;

    if (!drinksMenu) {
      return res.status(404).json({ message: "Drinks menu not found" });
    }

    let finalOfferPrice = offerPrice;

    if (isOffer) {
      if (!finalOfferPrice || finalOfferPrice === 0) {
        finalOfferPrice = price || drinksMenu.price;
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

    await drinksMenu.update({
      name,
      price,
      isUrgent,
      drinksCategoryId,
      isOutOfStock,
      isOffer: isOffer || false,
      offerPrice: isOffer ? finalOfferPrice : null,
      waiterCommission: isOffer ? waiterCommission : null,
      commissionType: isOffer ? commissionType : null,
    });

    // Flush ALL cache keys so the very next poll gets fresh data
    drinksCache.flushAll();

    res.status(200).json(drinksMenu);
  } catch (error) {
    console.error("Error updating drinks menu:", error);
    res.status(500).json({ message: "Error updating drinks menu", error });
  }
};

// Delete a drink menu item
const deleteDrinksMenu = async (req, res) => {
  try {
    const drinksMenu = await DrinksMenu.findByPk(req.params.id);

    if (!drinksMenu) {
      return res.status(404).json({ message: "Drinks menu not found" });
    }

    await drinksMenu.destroy();

    // ✅ Fixed: was referencing undefined `menuCache` — now uses `drinksCache`
    drinksCache.flushAll();

    res.status(204).send();
  } catch (error) {
    console.error("Error deleting drinks menu:", error);
    res.status(500).json({ message: "Error deleting drinks menu", error });
  }
};

module.exports = {
  getDrinksMenus,
  createDrinksMenu,
  getDrinksMenuById,
  updateDrinksMenu,
  deleteDrinksMenu,
};