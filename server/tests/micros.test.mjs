// Unit tests for the optional micronutrient mapping added to /analyze.
// Runs the REAL zod schema + REAL micronutrients() mapping from server.js (imported, server not started).
//   node --test tests/micros.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { MealAnalysis, micronutrients, round1 } from "../server.js";

const base = {
  is_food: true, meal_name: "Test meal", items: [],
  total_kcal: 500, total_protein_g: 30, total_carbs_g: 40, total_fat_g: 20,
  confidence: "medium", notes: "",
};

test("schema accepts nullable micros and a fully-omitted micros object", () => {
  // The model may return null for a micro it can't estimate.
  const withNulls = MealAnalysis.safeParse({
    ...base, total_fibre_g: null, total_sugar_g: null, total_sodium_mg: null, total_sat_fat_g: null,
    items: [],
  });
  assert.ok(withNulls.success, withNulls.success ? "" : JSON.stringify(withNulls.error?.issues));

  // Numeric micros parse too.
  const withNums = MealAnalysis.safeParse({
    ...base, total_fibre_g: 6, total_sugar_g: 12, total_sodium_mg: 800, total_sat_fat_g: 5,
    items: [],
  });
  assert.ok(withNums.success);
});

test("emits the EXACT iOS keys when the model provides totals", () => {
  const out = micronutrients({
    ...base, total_fibre_g: 6.24, total_sugar_g: 11.96, total_sodium_mg: 812.7, total_sat_fat_g: 4.55,
    items: [],
  });
  assert.deepEqual(out, { fibre_g: 6.2, sugar_g: 12, sodium_mg: 813, sat_fat_g: 4.6 });
});

test("omits (does NOT zero) micros that are unknown/null", () => {
  const out = micronutrients({
    ...base, total_fibre_g: 6, total_sugar_g: null, total_sodium_mg: null, total_sat_fat_g: null,
    items: [],
  });
  // fibre present; the three unknowns are absent entirely (not 0, not null).
  assert.deepEqual(out, { fibre_g: 6 });
  assert.ok(!("sugar_g" in out));
  assert.ok(!("sodium_mg" in out));
  assert.ok(!("sat_fat_g" in out));
});

test("distinguishes a real zero from unknown", () => {
  const out = micronutrients({ ...base, total_fibre_g: 0, total_sugar_g: null, items: [] });
  // 0 is a known value (e.g. plain water has 0 g fibre) → emit it.
  assert.equal(out.fibre_g, 0);
  assert.ok(!("sugar_g" in out));
});

test("falls back to summing item-level micros when the total is missing", () => {
  const out = micronutrients({
    ...base,
    items: [
      { name: "a", fibre_g: 2, sugar_g: 3, sodium_mg: 100, sat_fat_g: 1 },
      { name: "b", fibre_g: 1.5, sugar_g: null, sodium_mg: 250, sat_fat_g: null },
    ],
    // no total_* keys at all
  });
  assert.equal(out.fibre_g, 3.5);   // 2 + 1.5
  assert.equal(out.sugar_g, 3);     // only item a known
  assert.equal(out.sodium_mg, 350); // 100 + 250
  assert.equal(out.sat_fat_g, 1);   // only item a known
});

test("omits a micro when neither total nor any item value is known", () => {
  const out = micronutrients({
    ...base,
    items: [{ name: "a", fibre_g: null, sugar_g: null, sodium_mg: null, sat_fat_g: null }],
  });
  assert.deepEqual(out, {});
});

test("prefers the model-provided total over the item sum", () => {
  const out = micronutrients({
    ...base, total_fibre_g: 10,
    items: [{ name: "a", fibre_g: 2 }, { name: "b", fibre_g: 3 }],
  });
  assert.equal(out.fibre_g, 10); // total wins, not 5
});

test("round1 rounds to one decimal; sodium rounds to whole mg (checked via mapping)", () => {
  assert.equal(round1(4.55), 4.6);
  assert.equal(round1(6.24), 6.2);
  const out = micronutrients({ ...base, total_sodium_mg: 812.7, items: [] });
  assert.equal(out.sodium_mg, 813);
});
