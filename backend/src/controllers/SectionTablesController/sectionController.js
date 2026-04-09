// Get all sections with tables
const {
  Section,
  Table,
  Order,
  Menu,
  DrinksOrder,
  DrinksMenu,
} = require("../../models");


// Safe getters
const getOrderMenuId = (o) => o.menuId ?? o.menu_id ?? (o.menu && o.menu.id);
const getDrinkId = (o) => o.drinkId ?? o.drink_id ?? (o.drink && o.drink.id);
const getQty = (o) => Number(o.quantity ?? o.qty ?? o.qty_no ?? 1);
const getAmount = (o) => Number(o.amount ?? 0);

// Taxed amount calculator
const getTaxedAmount = (o, kind = "food") => {
  const qty = getQty(o);
  let basePrice = 0;

  if (kind === "food") {
    basePrice = o.amount != null ? Number(o.amount) : (o.menu?.price ?? 0) * qty;
    // Apply 5% GST
    return basePrice * 1.05;
  }

  if (kind === "drink") {
    basePrice = o.amount != null ? Number(o.amount) : (o.drink?.price ?? 0) * qty;
    if (o.drink?.applyVAT) {
      // Apply 10% VAT
      return basePrice * 1.10;
    } else {
      // Apply 5% GST
      return basePrice * 1.05;
    }
  }

  return o.amount != null ? Number(o.amount) : 0;
};



const aggregatePreserveShape = (arr, status, kind = "food") => {
  const filtered = arr.filter((o) => o.status === status);
  const map = {};

  filtered.forEach((o) => {
    const isCustom = o.is_custom === true;

    let key;
    if (isCustom) {
      const itemDesc = o.item_desc || o.note || "Custom Item";
      const kotNum = o.kotNumber || o.kot_number || "";
      key = `custom_${itemDesc}_${kotNum}`;
    } else {
      key = kind === "food" ? getOrderMenuId(o) : getDrinkId(o);
      if (key == null) return;
    }

    if (!map[key]) {
      let displayName;
      if (isCustom) {
        displayName =
          o.note ||
          o.item_desc ||
          (kind === "food" ? "Custom Item" : "Custom Drink");
      } else {
        displayName =
          (o.menu && o.menu.name) ||
          (o.drink && o.drink.name) ||
          o.item_desc ||
          null;
      }

      map[key] = {
        id: o.id,
        userId: o.userId ?? o.user_id ?? null,
        menuId:
          kind === "food" && !isCustom ? o.menuId ?? o.menu_id ?? key : undefined,
        drinkId:
          kind === "drink" && !isCustom
            ? o.drinkId ?? o.drink_id ?? key
            : undefined,
        item_desc: displayName,
        quantity: 0,
        taxedAmount: 0,
        taxedActualAmount: 0,
        amount_per_item: 0,
        table_number: o.table_number,
        section_number: o.section_number ?? o.sectionId ?? null,
        restaurent_table_number: o.restaurent_table_number ?? null,
        is_custom: isCustom,
        note: o.note || null,
        kotNumber: o.kotNumber ?? o.kot_number ?? null,
        kotNumbers: [],
        createdAt: o.createdAt,
        updatedAt: o.updatedAt,
        menu:
          kind === "food"
            ? isCustom
              ? { name: displayName }
              : o.menu
            : undefined,
        drink:
          kind === "drink"
            ? isCustom
              ? { name: displayName }
              : o.drink
            : undefined,
        mergedOrderIds: [],
        _rawTotal: 0,
      };
    }

    const entry = map[key];
    const qty = getQty(o) || 1;

    // ---------- Normalize unit price (per-item raw price) ----------
    const menuUnit =
      (o.menu && Number(o.menu.price)) || (o.drink && Number(o.drink.price));
    const incomingActual =
      o.taxesActualAmount != null ? Number(o.taxesActualAmount) : null;
    const incomingAmount = o.amount != null ? Number(o.amount) : null;

    let unitPrice = null;

    if (menuUnit != null && !Number.isNaN(menuUnit)) {
      unitPrice = menuUnit;
    } else if (incomingActual != null) {
      if (incomingActual >= qty && incomingActual / qty > 1) {
        unitPrice = incomingActual / qty;
      } else {
        unitPrice = incomingActual;
      }
    } else if (incomingAmount != null) {
      if (incomingAmount >= qty && incomingAmount / qty > 1) {
        unitPrice = incomingAmount / qty;
      } else {
        unitPrice = incomingAmount;
      }
    } else {
      unitPrice = 0;
    }

    // ✅ FIX: If this is a drink and the amount was saved *with tax included*,
    // back-calculate the base price before tax.
    if (kind === "drink" && isCustom) {
      // Since custom drinks are saved with VAT applied, remove it here.
      unitPrice = Number((unitPrice / 1.10).toFixed(2)); // remove 10% VAT
    }

    unitPrice = Number(unitPrice || 0);

    // accumulate
    entry.quantity += qty;
    entry._rawTotal += unitPrice * qty;
    if (o.id != null) entry.mergedOrderIds.push(o.id);

    const kn = o.kotNumber ?? o.kot_number ?? null;
    if (kn != null) entry.kotNumbers.push(kn);
  });

  // ---------- Finalize aggregation ----------
  const aggregated = Object.values(map).map((it) => {
    it.kotNumbers = Array.from(new Set(it.kotNumbers || []));
    const qty = it.quantity || 0;
    const rawTotal = Number(it._rawTotal || 0);

    it.amount_per_item = qty ? Number((rawTotal / qty).toFixed(2)) : 0;

    let taxRate = 0.05; // default GST

    if (kind === "drink") {
      const hasVAT = it.drink?.applyVAT === true;
      const isCustomDrink = it.is_custom === true;

      if (hasVAT || isCustomDrink) {
        taxRate = 0.10;
      } else {
        taxRate = 0.05;
      }
    }

    it.taxedActualAmount = Number(
      (it.amount_per_item * (1 + taxRate)).toFixed(2)
    );
    it.taxedAmount = Number((it.taxedActualAmount * qty).toFixed(2));

    delete it._rawTotal;
    it.mergedOrderIds = Array.from(new Set(it.mergedOrderIds || []));

    return it;
  });

  const totalAmount = Number(
    aggregated
      .reduce((s, it) => s + (Number(it.taxedAmount) || 0), 0)
      .toFixed(2)
  );

  return { aggregated, totalAmount, rawFiltered: filtered };
};



// async function getSections(req, res) {
//   try {
//     // =====================================================
//     // 1️⃣ Fetch sections with tables
//     // =====================================================
//     const sections = await Section.findAll({
//       include: [
//         {
//           model: Table,
//           as: 'tables',
//           order: [['display_number', 'ASC']],
//         },
//       ],
//       order: [['id', 'ASC']],
//     });

//     // =====================================================
//     // 2️⃣ Fetch ALL tables once (for merged_with resolution)
//     // =====================================================
//     const allTables = await Table.findAll({
//       attributes: ['id', 'display_number', 'sectionId'],
//       include: [
//         {
//           model: Section,
//           as: 'section',
//           attributes: ['id', 'name'],
//         },
//       ],
//     });

//     const tableLookup = allTables.reduce((acc, t) => {
//       acc[t.id] = {
//         tableId: t.id,
//         display_number: t.display_number,
//         sectionId: t.sectionId,
//         section_name: t.section?.name || null,
//       };
//       return acc;
//     }, {});

//     // =====================================================
//     // 3️⃣ Enrich sections & tables
//     // =====================================================
//     const enrichedSections = await Promise.all(
//       sections.map(async (section) => {
//         let activeTableCount = 0;
//         let sectionTotalAmount = 0;

//         const enrichedTables = await Promise.all(
//           section.tables.map(async (table) => {
//             const tableId = table.id;

//             const foodOrders = await Order.findAll({
//               where: { table_number: tableId },
//             });

//             const drinkOrders = await DrinksOrder.findAll({
//               where: { table_number: tableId },
//               include: [{ model: DrinksMenu, as: 'drink' }]
//             });



//             // ✅ FIX: Handle 'accepted' status as 'ongoing'
//             const splitOrdersByStatus = (orders) => ({
//               pending: orders.filter((o) => o.status === 'pending'),
//               ongoing: orders.filter((o) => o.status === 'ongoing' || o.status === 'accepted'),
//               completed: orders.filter((o) => o.status === 'completed'),
//             });

//             const food = splitOrdersByStatus(foodOrders);
//             const drinks = splitOrdersByStatus(drinkOrders);

//             // ✅ FIXED: Sum amounts from already-filtered orders (tax already included)
//             // With this:
//             const sumAmount = (orders, kind = 'food') => {
//               if (!orders || orders.length === 0) return 0;
//               const total = orders.reduce((sum, o) => {
//                 const qty = getQty(o);
//                 let basePrice = o.amount != null ? Number(o.amount) : 0;
//                 if (basePrice === 0 && o.menu?.price) {
//                   basePrice = Number(o.menu.price) * qty;
//                 } else if (basePrice === 0 && o.drink?.price) {
//                   basePrice = Number(o.drink.price) * qty;
//                 }

//                 let taxedTotal;
//                 if (kind === 'drink') {
//                   const applyVAT = o.drink?.applyVAT === true || o.is_custom === true;
//                   taxedTotal = applyVAT ? (basePrice * 1.10) : (basePrice * 1.05);
//                 } else {
//                   taxedTotal = basePrice * 1.05; // 5% GST for food
//                 }

//                 return sum + taxedTotal;
//               }, 0);
//               return Number(total.toFixed(2));
//             };


//             // ✅ Total for this table (tax already included in order amounts)
//             const tableTotal = Math.round(
//               sumAmount(food.pending) +
//               sumAmount(food.ongoing) +
//               sumAmount(food.completed) +
//               sumAmount(drinks.pending) +
//               sumAmount(drinks.ongoing) +
//               sumAmount(drinks.completed)
//             );

//             // ✅ Occupied = any order exists (merged / split / settle-up safe)
//             const isOccupied =
//               foodOrders.length > 0 || drinkOrders.length > 0;

//             if (isOccupied) activeTableCount++;
//             sectionTotalAmount += tableTotal;

//             // ---------------- MERGED DETAILS ----------------
//             let mergedWithDetails = [];
//             if (Array.isArray(table.merged_with) && table.merged_with.length) {
//               mergedWithDetails = table.merged_with
//                 .map((id) => tableLookup[id])
//                 .filter(Boolean);
//             }

//             return {
//               ...table.toJSON(),

//               merged_with_details: mergedWithDetails,

//               orders: {
//                 pendingOrders: food.pending,
//                 ongoingOrders: food.ongoing,
//                 completeOrders: food.completed,
//               },

//               drinksOrders: {
//                 pendingDrinksOrders: drinks.pending,
//                 ongoingDrinksOrders: drinks.ongoing,
//                 completeDrinksOrders: drinks.completed,
//               },

//               orderAmounts: {
//                 pendingAmount: Math.round(sumAmount(food.pending, 'food')),
//                 ongoingAmount: Math.round(sumAmount(food.ongoing, 'food')),
//                 completeAmount: Math.round(sumAmount(food.completed, 'food')),

//                 pendingDrinksAmount: Math.round(sumAmount(drinks.pending, 'drink')),
//                 ongoingDrinksAmount: Math.round(sumAmount(drinks.ongoing, 'drink')),
//                 completeDrinksAmount: Math.round(sumAmount(drinks.completed, 'drink')),

//                 totalAmount: Math.round(
//                   sumAmount(food.pending, 'food') + sumAmount(food.ongoing, 'food') + sumAmount(food.completed, 'food') +
//                   sumAmount(drinks.pending, 'drink') + sumAmount(drinks.ongoing, 'drink') + sumAmount(drinks.completed, 'drink')
//                 ),
//               },
//             };
//           })
//         );

//         return {
//           ...section.toJSON(),
//           summary: {
//             activeTableCount,
//             sectionTotalAmount: Math.round(sectionTotalAmount),
//           },
//           tables: enrichedTables,
//         };
//       })
//     );

//     // =====================================================
//     // 4️⃣ Final response
//     // =====================================================
//     return res.json(enrichedSections);

//   } catch (err) {
//     console.error('❌ getSections error:', err);
//     return res.status(500).json({
//       message: 'Failed to fetch sections',
//       error: err.message,
//     });
//   }
// }







// Get section by ID


async function getSections(req, res) {
  try {
    const sections = await Section.findAll({
      include: [
        {
          model: Table,
          as: 'tables',
          order: [['display_number', 'ASC']],
        },
      ],
      order: [['id', 'ASC']],
    });

    const allTables = await Table.findAll({
      attributes: ['id', 'display_number', 'sectionId'],
      include: [
        {
          model: Section,
          as: 'section',
          attributes: ['id', 'name'],
        },
      ],
    });

    const tableLookup = allTables.reduce((acc, t) => {
      acc[t.id] = {
        tableId: t.id,
        display_number: t.display_number,
        sectionId: t.sectionId,
        section_name: t.section?.name || null,
      };
      return acc;
    }, {});

    const enrichedSections = await Promise.all(
      sections.map(async (section) => {

        const enrichedTables = await Promise.all(
          section.tables.map(async (table) => {
            const tableId = table.id;

            const foodOrders = await Order.findAll({
              where: { table_number: tableId },
            });

            const drinkOrders = await DrinksOrder.findAll({
              where: { table_number: tableId },
              include: [{ model: DrinksMenu, as: 'drink' }],
            });

            const splitOrdersByStatus = (orders) => ({
              pending: orders.filter((o) => o.status === 'pending'),
              ongoing: orders.filter((o) => o.status === 'ongoing' || o.status === 'accepted'),
              completed: orders.filter((o) => o.status === 'completed'),
            });

            const food = splitOrdersByStatus(foodOrders);
            const drinks = splitOrdersByStatus(drinkOrders);

            // ✅ FIXED sumAmount: o.amount is the BASE price stored in DB.
            // Tax is applied here to get the taxed total.
            const sumAmount = (orders, kind = 'food') => {
  if (!orders || orders.length === 0) return 0;
  const total = orders.reduce((sum, o) => {
    const base = Number(o.amount ?? 0);
    if (kind === 'food') return sum + base * 1.05;
    if (kind === 'drink') {
      // ✅ applyVAT field takes priority over is_custom
      // If applyVAT is explicitly false, never apply 10% even for custom drinks
      const apply10VAT =
        o.applyVAT === true ||
        (o.is_custom === true && o.applyVAT !== false && o.drink?.applyVAT === true);
      return sum + base * (apply10VAT ? 1.10 : 1.05);
    }
    return sum;
  }, 0);
  return Number(total.toFixed(2));
};

            const pFood   = sumAmount(food.pending,    'food');
            const oFood   = sumAmount(food.ongoing,    'food');
            const cFood   = sumAmount(food.completed,  'food');
            const pDrink  = sumAmount(drinks.pending,  'drink');
            const oDrink  = sumAmount(drinks.ongoing,  'drink');
            const cDrink  = sumAmount(drinks.completed,'drink');

            const tableTotal = Math.round(pFood + oFood + cFood + pDrink + oDrink + cDrink);

            let mergedWithDetails = [];
            if (Array.isArray(table.merged_with) && table.merged_with.length) {
              mergedWithDetails = table.merged_with.map((id) => tableLookup[id]).filter(Boolean);
            }

            return {
              ...table.toJSON(),
              merged_with_details: mergedWithDetails,
              orders: {
                pendingOrders:  food.pending,
                ongoingOrders:  food.ongoing,
                completeOrders: food.completed,
              },
              drinksOrders: {
                pendingDrinksOrders:  drinks.pending,
                ongoingDrinksOrders:  drinks.ongoing,
                completeDrinksOrders: drinks.completed,
              },
              orderAmounts: {
                pendingAmount:        Math.round(pFood),
                ongoingAmount:        Math.round(oFood),
                completeAmount:       Math.round(cFood),
                pendingDrinksAmount:  Math.round(pDrink),
                ongoingDrinksAmount:  Math.round(oDrink),
                completeDrinksAmount: Math.round(cDrink),
                totalAmount:          tableTotal,
              },
            };
          })
        );

        // ✅ KEY FIX: Compute section summary from already-correct table totals
        // instead of re-accumulating with potentially wrong tax logic above.
        let activeTableCount = 0;
        let sectionTotalAmount = 0;

        for (const t of enrichedTables) {
          const total = t.orderAmounts?.totalAmount ?? 0;
          if (total > 0) {
            activeTableCount++;
            sectionTotalAmount += total;
          }
        }

        return {
          ...section.toJSON(),
          summary: {
            activeTableCount,
            sectionTotalAmount: Math.round(sectionTotalAmount),
          },
          tables: enrichedTables,
        };
      })
    );

    return res.json(enrichedSections);

  } catch (err) {
    console.error('❌ getSections error:', err);
    return res.status(500).json({
      message: 'Failed to fetch sections',
      error: err.message,
    });
  }
}



const getSectionById = async (req, res) => {
  try {
    const section = await Section.findByPk(req.params.id, {
      include: [{ model: Table, as: "tables" }],
    });
    if (!section) return res.status(404).json({ message: "Section not found" });
    res.json(section);
  } catch (error) {
    console.error("Error fetching section:", error);
    res
      .status(500)
      .json({ message: "Error fetching section", error: error.message });
  }
};

// Create new section
const createSection = async (req, res) => {
  try {
    const { name, description } = req.body;
    const section = await Section.create({ name, description });

    const io = req.app.get("io");
    io.emit("new_section", section);

    res.status(201).json(section);
  } catch (error) {
    console.error("Error creating section:", error);
    res
      .status(500)
      .json({ message: "Error creating section", error: error.message });
  }
};

// Update section
const updateSection = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description } = req.body;

    const section = await Section.findByPk(id);
    if (!section) return res.status(404).json({ message: "Section not found" });

    await section.update({
      name: name || section.name,
      description: description || section.description,
    });
    res.status(200).json(section);
  } catch (error) {
    console.error("Error updating section:", error);
    res
      .status(500)
      .json({ message: "Error updating section", error: error.message });
  }
};

// Delete section
const deleteSection = async (req, res) => {
  try {
    const { id } = req.params;
    const section = await Section.findByPk(id);
    if (!section) return res.status(404).json({ message: "Section not found" });

    // Delete all tables associated with the section
    await Table.destroy({ where: { sectionId: id } });

    // Delete the section itself
    await section.destroy();

    res.json({ message: "Section and associated tables deleted successfully" });
  } catch (error) {
    console.error("Error deleting section:", error);
    res
      .status(500)
      .json({ message: "Error deleting section", error: error.message });
  }
};

module.exports = {
  getSections,
  getSectionById,
  createSection,
  updateSection,
  deleteSection,
};