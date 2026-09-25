// Unit tests for the Open Food Facts text-search integration in /foods:
//   - offFood() normalises an OFF product into the shared per-100 g shape
//   - mergeFoods() merges local-DB + USDA + OFF, dedupes by barcode and name+brand, and ranks
//     complete-macro / relevant entries first while dropping nothing that a source already vetted.
// Runs the REAL functions from server.js (imported; the server is not started).
//   node --test tests/foods.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { offFood, mergeFoods, foodKey, macroCompleteness } from "../server.js";

// A realistic OFF search-result product (Heineken lager), energy in kcal + salt-only sodium.
const heinekenOFF = {
  code: "8712000000000",
  product_name: "Heineken",
  product_name_en: "Heineken Lager Beer",
  brands: "Heineken, Heineken International",
  serving_size: "330 ml",
  serving_quantity: 330,
  nutriments: {
    "energy-kcal_100g": 42, "proteins_100g": 0.3, "carbohydrates_100g": 3.2,
    "fat_100g": 0, "sugars_100g": 0, "salt_100g": 0.01, "saturated-fat_100g": 0,
  },
};

test("offFood normalises an OFF product into the shared per-100 g shape", () => {
  const f = offFood(heinekenOFF, heinekenOFF.code);
  assert.ok(f, "expected a food, not null");
  assert.equal(f.id, "off:8712000000000");
  assert.equal(f.name, "Heineken Lager Beer");   // product_name_en preferred
  assert.equal(f.brand, "Heineken");             // first brand only
  assert.equal(f.kind, "branded");
  assert.equal(f.barcode, "8712000000000");
  assert.equal(f.per100.kcal, 42);
  assert.equal(f.per100.protein, 0.3);
  assert.equal(f.per100.carbs, 3.2);
  // salt (g) → sodium (mg): 0.01 g salt * 400 = 4 mg
  assert.equal(f.per100.sodium, 4);
  assert.equal(f.servings.length, 1);
  assert.equal(f.servings[0].grams, 330);
});

test("offFood converts kJ energy to kcal when kcal is absent", () => {
  const f = offFood({ code: "1", product_name: "X", nutriments: { "energy_100g": 418.4, "proteins_100g": 1 } }, "1");
  assert.ok(Math.abs(f.per100.kcal - 100) < 0.5); // 418.4 kJ / 4.184 ≈ 100 kcal
});

test("offFood returns null for an entry with no kcal and no protein (macro-empty)", () => {
  const f = offFood({ code: "2", product_name: "Mystery", nutriments: {} }, "2");
  assert.equal(f, null);
});

test("macroCompleteness scores 0..4 by present positive macros", () => {
  assert.equal(macroCompleteness({ per100: { kcal: 42, protein: 0.3, carbs: 3.2, fat: 0 } }), 3); // fat 0 not counted
  assert.equal(macroCompleteness({ per100: { kcal: 200, protein: 10, carbs: 20, fat: 5 } }), 4);
  assert.equal(macroCompleteness({ per100: {} }), 0);
});

test("mergeFoods keeps local first and appends ranked live results", () => {
  const local = [{ name: "Homemade Beer", brand: null, kind: "generic", per100: { kcal: 43, protein: 0.5, carbs: 3.6, fat: 0 } }];
  const usda = [{ id: 1, name: "Beer, regular", brand: null, kind: "generic", per100: { kcal: 43, protein: 0.5, carbs: 3.6, fat: 0 } }];
  const off = [offFood(heinekenOFF, heinekenOFF.code)];
  const out = mergeFoods({ local, usda, off, query: "heineken beer" });
  assert.equal(out[0].name, "Homemade Beer", "local stays in front");
  // The branded Heineken (matches 'heineken') should be present in the live tail.
  assert.ok(out.some((f) => f.barcode === "8712000000000"), "OFF branded result is included");
});

test("mergeFoods dedupes by barcode across USDA and OFF", () => {
  const usda = [{ id: 9, name: "Heineken Beer", brand: "Heineken", kind: "branded", barcode: "8712000000000", per100: { kcal: 42, protein: 0.3, carbs: 3.2, fat: 0 } }];
  const off = [offFood(heinekenOFF, heinekenOFF.code)]; // same barcode
  const out = mergeFoods({ local: [], usda, off, query: "heineken" });
  const withBarcode = out.filter((f) => f.barcode === "8712000000000");
  assert.equal(withBarcode.length, 1, "barcode dedupe keeps one");
  assert.equal(withBarcode[0].id, 9, "USDA (listed first) wins the dedupe");
});

test("mergeFoods dedupes by normalised name+brand when no barcode", () => {
  const usda = [{ id: 1, name: "Coca-Cola", brand: "Coca Cola", kind: "branded", per100: { kcal: 42, protein: 0, carbs: 10.6, fat: 0 } }];
  const off = [{ id: "off:x", name: "coca cola", brand: "coca cola", kind: "branded", per100: { kcal: 42, protein: 0, carbs: 10.6, fat: 0 } }];
  const out = mergeFoods({ local: [], usda, off, query: "coca cola" });
  assert.equal(out.length, 1, "same name+brand collapses to one");
  assert.equal(foodKey(usda[0]), foodKey(off[0]));
});

test("mergeFoods ranks macro-complete entries ahead of macro-thin ones at equal relevance", () => {
  const complete = { id: "c", name: "Fanta Orange", brand: "Fanta", kind: "branded", per100: { kcal: 48, protein: 0, carbs: 11.8, fat: 0.1 } };
  const thin = { id: "t", name: "Fanta Orange", brand: "Fanta Zero", kind: "branded", per100: { kcal: 0, protein: 0.2, carbs: 0, fat: 0 } };
  // Feed thin first to prove ranking, not insertion order, decides.
  const out = mergeFoods({ local: [], usda: [], off: [thin, complete], query: "fanta orange" });
  assert.equal(out[0].id, "c", "the complete-macro entry ranks first");
});

test("mergeFoods honours the cap", () => {
  const off = Array.from({ length: 60 }, (_, i) => ({ id: `off:${i}`, name: `Snack ${i}`, brand: `B${i}`, kind: "branded", per100: { kcal: 100 + i, protein: 5, carbs: 10, fat: 2 } }));
  const out = mergeFoods({ local: [], usda: [], off, query: "snack", cap: 40 });
  assert.equal(out.length, 40);
});
