// utils/unitConverter.js

const conversionRates = {
  gm: { kg: 0.001, gm: 1 },
  kg: { gm: 1000, kg: 1 },
  ml: { l: 0.001, ml: 1, tbsp: 1 / 15, tsp: 1 / 5 },
  l: { ml: 1000, l: 1, tbsp: 66.6667, tsp: 200 },
  tbsp: { ml: 15, l: 0.015, tbsp: 1, tsp: 3 },
  tsp: { ml: 5, l: 0.005, tbsp: 1 / 3, tsp: 1 },
};

const convertUnits = (quantity, fromUnit, toUnit) => {
  fromUnit = fromUnit.toLowerCase();
  toUnit = toUnit.toLowerCase();

  if (!conversionRates[fromUnit] || !conversionRates[fromUnit][toUnit]) {
    throw new Error(`Conversion from ${fromUnit} to ${toUnit} not supported.`);
  }

  return quantity * conversionRates[fromUnit][toUnit];
};

module.exports = { convertUnits };
