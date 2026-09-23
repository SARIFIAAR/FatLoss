// Fat Loss Coach — meal photo analyzer + admin dashboard.
//   POST /analyze        { image: <base64 jpeg>, mediaType?, hint?, context? }  Authorization: Bearer <Firebase ID token>
//                        or { text: "2 eggs and toast", context? } for a written description (no photo)
//   GET  /barcode?code=  packaged product by EAN/UPC: Open Food Facts, then USDA Branded (Bearer token)
//   GET  /foods?q=...    USDA FoodData Central search, normalised to per-100 g macros + household portions (Bearer token)
//   GET  /health
//   GET  /admin          coach dashboard (needs ADMIN_KEY); /admin/api/* JSON behind header x-admin-key
// Verifies the Firebase token against Google's public keys (no service account needed for that), then asks
// Claude for a structured nutrition estimate. With FIREBASE_SERVICE_ACCOUNT set, every scan is also logged
// to Firestore `scans/` and the dashboard can read each user's per-day rows written by the app.
import http from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import * as db from "./firestore.js";
import * as wear from "./integrations.js";

const PORT = Number(process.env.PORT ?? 8080);
const PROJECT = process.env.FIREBASE_PROJECT_ID ?? "fat-loss-6516d";
const MODEL = process.env.MODEL ?? "claude-opus-5";          // e.g. fly secrets set MODEL=claude-sonnet-5
const ADMIN_KEY = process.env.ADMIN_KEY ?? "";               // fly secrets set ADMIN_KEY=<long random string>
const MAX_BODY = 10 * 1024 * 1024;
const USDA_KEY = process.env.USDA_API_KEY ?? "DEMO_KEY";      // free key: https://fdc.nal.usda.gov/api-key-signup (DEMO_KEY = 30 req/h)

// When imported by a test (not run directly) we skip the hard bootstrap requirements and the server.
const IS_MAIN = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (IS_MAIN && !process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set");
  process.exit(1);
}
if (!db.enabled) console.warn("FIREBASE_SERVICE_ACCOUNT not set: scans are not logged and /admin has no data");
if (!ADMIN_KEY) console.warn("ADMIN_KEY not set: /admin is disabled");
if (USDA_KEY === "DEMO_KEY") console.warn("USDA_API_KEY not set: food search uses DEMO_KEY (30 requests/hour)");

const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;
const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);
const ADMIN_HTML = IS_MAIN ? readFileSync(new URL("./admin.html", import.meta.url)) : Buffer.alloc(0);

// Optional micronutrients. null = genuinely cannot be estimated (unknown ≠ zero). The model must
// only fill these when it can reasonably estimate them; barcode foods already carry them client-side.
const nullableMicro = (unit) => z.number().nullable().describe(`${unit}; null if it cannot be reasonably estimated`);

const FoodItem = z.object({
  name: z.string().describe("Short food name, e.g. 'Grilled chicken breast'"),
  portion: z.string().describe("Estimated portion in plain words, e.g. '150 g' or '1 cup'"),
  grams: z.number().describe("Estimated weight in grams"),
  kcal: z.number(),
  protein_g: z.number(),
  carbs_g: z.number(),
  fat_g: z.number(),
  fibre_g: nullableMicro("Dietary fibre in grams"),
  sugar_g: nullableMicro("Total sugars in grams"),
  sodium_mg: nullableMicro("Sodium in milligrams"),
  sat_fat_g: nullableMicro("Saturated fat in grams"),
});
const MealAnalysis = z.object({
  is_food: z.boolean().describe("false if the photo does not show food or drink"),
  meal_name: z.string().describe("A 2-5 word name for the whole meal"),
  items: z.array(FoodItem),
  total_kcal: z.number(),
  total_protein_g: z.number(),
  total_carbs_g: z.number(),
  total_fat_g: z.number(),
  total_fibre_g: nullableMicro("Total dietary fibre in grams; null if it cannot be reasonably estimated"),
  total_sugar_g: nullableMicro("Total sugars in grams; null if it cannot be reasonably estimated"),
  total_sodium_mg: nullableMicro("Total sodium in milligrams; null if it cannot be reasonably estimated"),
  total_sat_fat_g: nullableMicro("Total saturated fat in grams; null if it cannot be reasonably estimated"),
  confidence: z.enum(["low", "medium", "high"]),
  notes: z.string().describe("One sentence: assumptions made (hidden oils, sauces, portion uncertainty). Empty if none."),
});

function systemPrompt(ctx, source = "photo") {
  const who = [];
  if (ctx?.currentWeightKg) who.push(`currently ~${Math.round(ctx.currentWeightKg)} kg`);
  if (ctx?.goalWeightKg) who.push(`goal ${Math.round(ctx.goalWeightKg)} kg`);
  if (ctx?.kcalTarget) who.push(`target ${ctx.kcalTarget} kcal/day`);
  if (ctx?.proteinTarget) who.push(`${ctx.proteinTarget} g protein/day`);
  const profile = who.length ? ` (${who.join(", ")})` : "";
  const micros = `Also estimate, per item and as a meal total, four micronutrients: dietary fibre (g), total sugars (g), sodium (mg) and saturated fat (g). Use standard nutrition-database values for the identified foods. Report these honestly: if a micronutrient genuinely cannot be reasonably estimated for a food (or the whole meal), return null for it — never guess and never return 0 for an unknown value (0 means "known to contain none", not "unknown"). Micronutrient totals should equal the sum of the items' known values.`;
  if (source === "text") {
    return `You are a registered dietitian estimating nutrition from a client's written description of a meal, for a fat-loss client${profile}.
Identify each distinct food or drink in the description. Use the quantities the client gives; when a quantity is missing, assume a typical single serving and say so in notes. Estimate calories and macros using standard nutrition databases (USDA). Account for likely cooking oils, dressings and sauces. Totals must equal the sum of the items. ${micros} If the text does not describe food or drink, set is_food to false and return empty items with zero totals.`;
  }
  return `You are a registered dietitian estimating nutrition from a single meal photo for a fat-loss client${profile}.
Identify each distinct food or drink, estimate the portion from visual cues (plate size, utensils, hand, packaging), and estimate calories and macros using standard nutrition databases (USDA). Account for likely cooking oils, dressings and sauces. When unsure, choose the more common preparation and say so in notes. Totals must equal the sum of the items. ${micros} If the image does not show food or drink, set is_food to false and return empty items with zero totals.`;
}

const BodyComp = z.object({
  is_report: z.boolean().describe("false if the photo is not a body-composition report"),
  weight_kg: z.number().describe("Total body weight in kg (convert from lb if needed)"),
  body_fat_pct: z.number().describe("Percent body fat (PBF). 0 if not shown"),
  fat_mass_kg: z.number().describe("Body fat mass in kg. 0 if not shown"),
  skeletal_muscle_kg: z.number().describe("Skeletal muscle mass (SMM) in kg. 0 if not shown"),
  visceral_fat: z.number().describe("Visceral fat level (unitless). 0 if not shown"),
  bmr_kcal: z.number().describe("Basal metabolic rate in kcal. 0 if not shown"),
  confidence: z.enum(["low", "medium", "high"]),
  notes: z.string().describe("One sentence on anything ambiguous or converted. Empty if none."),
});

function bodyPrompt() {
  return `You are reading a body-composition analysis report (e.g. InBody, Tanita, or a smart-scale summary) from a single photo, for a fat-loss client.
Extract the printed numbers exactly as shown — do not estimate or invent values. Map them to: total weight, percent body fat (PBF), body fat mass, skeletal muscle mass (SMM), visceral fat level, and basal metabolic rate (BMR). Convert pounds to kilograms if the report is in lb. If a field is not present on the report, return 0 for it. If the photo is not a body-composition report, set is_report to false and return zeros.`;
}

const ALLOWED_MEDIA = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function verifyUser(req) {
  const auth = req.headers.authorization ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!token) throw new HttpError(401, "Sign in to analyze meals.");
  try {
    const { payload } = await jwtVerify(token, JWKS, {
      issuer: `https://securetoken.google.com/${PROJECT}`,
      audience: PROJECT,
    });
    if (!payload.sub) throw new Error("no sub");
    return { uid: payload.sub, email: payload.email ?? null };
  } catch {
    throw new HttpError(401, "Your session expired. Sign in again.");
  }
}

function requireAdmin(req) {
  if (!ADMIN_KEY) throw new HttpError(503, "ADMIN_KEY is not configured on the server.");
  const given = req.headers["x-admin-key"] ?? "";
  const a = Buffer.from(String(given)), b = Buffer.from(ADMIN_KEY);
  if (a.length !== b.length || !timingSafeEqual(a, b)) throw new HttpError(401, "Wrong admin key.");
  if (!db.enabled) throw new HttpError(503, "FIREBASE_SERVICE_ACCOUNT is not configured on the server.");
}

function readJSON(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new HttpError(413, "Image too large — resize to ~1024 px.")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
      catch { reject(new HttpError(400, "Body must be JSON.")); }
    });
    req.on("error", reject);
  });
}

async function analyzeBody(body) {
  const image = body?.image;
  const mediaType = body?.mediaType ?? "image/jpeg";
  const hasImage = typeof image === "string" && image.length >= 100;
  if (!hasImage) throw new HttpError(400, "Send a base64 JPEG of the report in `image`.");
  if (!ALLOWED_MEDIA.has(mediaType)) throw new HttpError(400, `Unsupported mediaType ${mediaType}.`);
  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 2000,
      system: bodyPrompt(),
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { format: zodOutputFormat(BodyComp), effort: "medium" },
      messages: [{ role: "user", content: [
        { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
        { type: "text", text: "Extract the body-composition numbers from this report." },
      ] }],
    });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) throw new HttpError(429, "Busy, try again in a moment.");
    if (err instanceof Anthropic.APIConnectionError) throw new HttpError(503, "Could not reach the model.");
    if (err instanceof Anthropic.APIError) { console.error("anthropic", err.status, err.message); throw new HttpError(502, `Model error ${err.status ?? ""}.`); }
    throw err;
  }
  if (response.stop_reason === "refusal") throw new HttpError(422, "The model declined to analyze this image.");
  const out = response.content.find((b) => b.type === "text")?.text ?? "";
  const parsed = BodyComp.safeParse(JSON.parse(out));
  if (!parsed.success) throw new HttpError(502, "Malformed analysis.");
  return { ...parsed.data, model: response.model,
           usage: { input: response.usage.input_tokens, output: response.usage.output_tokens } };
}

async function analyze(body) {
  const image = body?.image;
  const text = typeof body?.text === "string" ? body.text.trim().slice(0, 1000) : "";
  const mediaType = body?.mediaType ?? "image/jpeg";
  const hint = typeof body?.hint === "string" ? body.hint.trim() : "";
  const ctx = body?.context && typeof body.context === "object" ? body.context : null;
  const hasImage = typeof image === "string" && image.length >= 100;
  if (!hasImage && !text) throw new HttpError(400, "Send a base64 JPEG in `image` or a description in `text`.");
  if (hasImage && !ALLOWED_MEDIA.has(mediaType)) throw new HttpError(400, `Unsupported mediaType ${mediaType}.`);
  const content = hasImage
    ? [
        { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
        { type: "text", text: hint ? `Estimate the nutrition of this meal. Extra context from the user: ${hint}` : "Estimate the nutrition of this meal." },
      ]
    : [{ type: "text", text: `Estimate the nutrition of this meal: "${text}"${hint ? `\nExtra context from the user: ${hint}` : ""}` }];

  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 4000,
      system: systemPrompt(ctx, hasImage ? "photo" : "text"),
      // Safety-classifier refusals are re-run on a fallback model inside the same call.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { format: zodOutputFormat(MealAnalysis), effort: "medium" },
      messages: [{ role: "user", content }],
    });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) throw new HttpError(429, "Busy, try again in a moment.");
    if (err instanceof Anthropic.APIConnectionError) throw new HttpError(503, "Could not reach the model.");
    if (err instanceof Anthropic.APIError) { console.error("anthropic", err.status, err.message); throw new HttpError(502, `Model error ${err.status ?? ""}.`); }
    throw err;
  }
  if (response.stop_reason === "refusal") throw new HttpError(422, hasImage ? "The model declined to analyze this image." : "The model declined to analyze this text.");
  const out = response.content.find((b) => b.type === "text")?.text ?? "";
  const parsed = MealAnalysis.safeParse(JSON.parse(out));
  if (!parsed.success) throw new HttpError(502, "Malformed analysis.");
  const d = parsed.data;
  // Map the four optional micros to the EXACT keys the iOS MealScanner.Analysis decodes
  // (fibre_g/sugar_g/sodium_mg/sat_fat_g). Honest numbers: emit a key ONLY when a real value
  // exists — omit it entirely when unknown (unknown ≠ 0). Older app builds ignore these keys,
  // so the kcal/macros contract stays backward-compatible.
  const micros = micronutrients(d);
  return {
    is_food: d.is_food, meal_name: d.meal_name, items: d.items,
    total_kcal: d.total_kcal, total_protein_g: d.total_protein_g,
    total_carbs_g: d.total_carbs_g, total_fat_g: d.total_fat_g,
    confidence: d.confidence, notes: d.notes,
    ...micros,
    model: response.model,
    usage: { input: response.usage.input_tokens, output: response.usage.output_tokens },
  };
}

/** Meal-total micros in iOS field names, only for values that were actually estimated.
 *  Falls back to summing item-level values when the model gave items but omitted the total.
 *  A micro is included only if at least one contributing value is a finite number; a total that
 *  is null with no numeric item data is omitted (unknown ≠ 0). */
function micronutrients(d) {
  const items = Array.isArray(d.items) ? d.items : [];
  const pick = (totalKey, itemKey) => {
    const t = d[totalKey];
    if (typeof t === "number" && Number.isFinite(t)) return t;
    // Model omitted the meal total but may have filled item values — sum the known ones.
    const known = items.map((i) => i?.[itemKey]).filter((v) => typeof v === "number" && Number.isFinite(v));
    return known.length ? known.reduce((a, b) => a + b, 0) : null;
  };
  const out = {};
  const fibre = pick("total_fibre_g", "fibre_g");     if (fibre != null) out.fibre_g = round1(fibre);
  const sugar = pick("total_sugar_g", "sugar_g");     if (sugar != null) out.sugar_g = round1(sugar);
  const sodium = pick("total_sodium_mg", "sodium_mg"); if (sodium != null) out.sodium_mg = Math.round(sodium);
  const satFat = pick("total_sat_fat_g", "sat_fat_g"); if (satFat != null) out.sat_fat_g = round1(satFat);
  return out;
}
const round1 = (n) => Math.round(n * 10) / 10;

// ---- USDA FoodData Central search --------------------------------------------------------------

const NUTRIENT = { kcal: [1008, 2048, 2047], protein: [1003], carbs: [1005], fat: [1004],
                   fibre: [1079, 2033], sugar: [2000, 1063], sodium: [1093], satFat: [1258] };
// Our own nutrition DB (USDA SR Legacy imported by build-fooddb.mjs + branded lookups cached at runtime).
let foodDB = null;
try {
  const Database = (await import("better-sqlite3")).default;
  const path = existsSync("data/foods.db") ? "data/foods.db" : "/data/foods.db";
  if (existsSync(path)) { foodDB = new Database(path); foodDB.pragma("journal_mode = WAL");
    console.log("food DB:", foodDB.prepare("SELECT COUNT(*) c FROM foods").get().c, "foods"); }
} catch (e) { console.warn("food DB unavailable:", e.message); }

function rowToFood(r) {
  return { id: r.id, name: r.name, brand: r.brand, kind: r.kind, category: r.category,
    per100: { kcal: r.kcal, protein: r.protein, carbs: r.carbs, fat: r.fat,
              fibre: r.fibre, sugar: r.sugar, sodium: r.sodium, satFat: r.satFat },
    servings: JSON.parse(r.servings || "[]"), barcode: r.barcode };
}
/** Local full-text search of our own DB, ranked: whole-word matches → fewest extra words → verified. */
function localSearch(query, limit = 25) {
  if (!foodDB) return [];
  const q = query.toLowerCase().trim();
  const rows = foodDB.prepare("SELECT * FROM foods WHERE name_lc LIKE ? LIMIT 300").all(`%${q}%`);
  const tokens = q.split(/[^a-z0-9]+/).filter((w) => w.length > 1);
  return rows.map((r) => {
    const words = r.name_lc.split(/[^a-z0-9]+/).filter(Boolean);
    const matched = tokens.filter((t) => words.includes(t)).length;
    const missing = tokens.length - matched;
    const extra = Math.max(0, words.length - tokens.length);
    return { f: rowToFood(r), key: missing * 1000 + extra * 10 + (r.verified ? 0 : 1) };
  }).sort((a, b) => a.key - b.key).slice(0, limit).map((x) => x.f);
}
/** Persist a branded/barcode food into our DB so it's owned + offline next time (the moat). */
function cacheFood(f) {
  if (!foodDB || !f) return;
  try {
    foodDB.prepare(`INSERT OR REPLACE INTO foods
      (id,name,name_lc,brand,kind,category,kcal,protein,carbs,fat,fibre,sugar,sodium,satFat,servings,barcode,verified)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)`).run(
      f.id ?? `off-${f.barcode}`, f.name, (f.name||"").toLowerCase(), f.brand ?? null, f.kind ?? "branded", f.category ?? null,
      f.per100.kcal||0, f.per100.protein||0, f.per100.carbs||0, f.per100.fat||0,
      f.per100.fibre||0, f.per100.sugar||0, f.per100.sodium||0, f.per100.satFat||0,
      JSON.stringify(f.servings ?? []), f.barcode ?? null);
  } catch (e) { /* non-fatal */ }
}

const foodCache = new Map(); // query -> { at, foods }
const FOOD_CACHE_TTL = 6 * 60 * 60 * 1000;

function nutrient(list, ids) {
  for (const id of ids) {
    const hit = list.find((n) => n.nutrientId === id);
    if (hit && typeof hit.value === "number") return hit.value;
  }
  return 0;
}
function titleCase(str) {
  return str.toLowerCase().replace(/(^|[\s(/-])([a-z])/g, (m, pre, c) => pre + c.toUpperCase());
}
function normaliseFood(f) {
  const branded = f.dataType === "Branded";
  const per100 = {
    kcal: nutrient(f.foodNutrients, NUTRIENT.kcal), protein: nutrient(f.foodNutrients, NUTRIENT.protein),
    carbs: nutrient(f.foodNutrients, NUTRIENT.carbs), fat: nutrient(f.foodNutrients, NUTRIENT.fat),
    fibre: nutrient(f.foodNutrients, NUTRIENT.fibre), sugar: nutrient(f.foodNutrients, NUTRIENT.sugar),
    sodium: nutrient(f.foodNutrients, NUTRIENT.sodium), satFat: nutrient(f.foodNutrients, NUTRIENT.satFat),
  };
  const servings = [];
  if (branded && f.servingSize > 0 && /^(g|grm|ml|mlt)$/i.test(f.servingSizeUnit ?? "")) {
    const label = (f.householdServingFullText || "").trim();
    servings.push({ label: label ? `${label} (${Math.round(f.servingSize)} g)` : `1 serving (${Math.round(f.servingSize)} g)`, grams: f.servingSize });
  }
  for (const m of f.foodMeasures ?? []) {
    if (!m.gramWeight || /not specified/i.test(m.disseminationText ?? "")) continue;
    servings.push({ label: `${m.disseminationText} (${Math.round(m.gramWeight)} g)`, grams: m.gramWeight });
    if (servings.length >= 6) break;
  }
  return {
    id: f.fdcId,
    name: branded ? titleCase(f.description) : f.description,
    brand: branded ? titleCase(f.brandName || f.brandOwner || "") || null : null,
    kind: branded ? "branded" : "generic",
    category: f.foodCategory ?? null,
    per100,
    servings,
  };
}

async function searchFoods(q) {
  const query = q.trim().slice(0, 100);
  if (query.length < 2) return [];
  const cached = foodCache.get(query.toLowerCase());
  if (cached && Date.now() - cached.at < FOOD_CACHE_TTL) return cached.foods;
  // Our own DB first — instant, owned, offline-capable. Only hit live USDA if it's thin.
  const local = localSearch(query, 25);
  if (local.length >= 8) { foodCache.set(query.toLowerCase(), { at: Date.now(), foods: local }); return local; }
  let res;
  try {
    res = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(USDA_KEY)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query, pageSize: 40, dataType: ["Survey (FNDDS)", "SR Legacy", "Foundation", "Branded"] }),
      signal: AbortSignal.timeout(12_000),
    });
  } catch (err) {
    throw new HttpError(503, "Could not reach the food database.");
  }
  if (res.status === 429) throw new HttpError(429, "Food database is busy — try again in a minute.");
  if (!res.ok) { console.error("usda", res.status, (await res.text()).slice(0, 200)); throw new HttpError(502, "Food database error."); }
  const json = await res.json();
  const foods = (json.foods ?? []).map(normaliseFood).filter((f) => f.per100.kcal > 0 || f.per100.protein > 0);
  // Generic (as-eaten) foods first — plain entries ("Banana, raw") before heavily qualified ones ("Bananas, dehydrated,
  // or banana powder") — then packaged products. Within a tier USDA's relevance order is kept.
  // Rank: entries containing every query word first, then the fewest extra words ("Banana, raw" beats
  // "Banana pudding, home recipe"), then USDA's relevance order.
  const stem = (w) => w.replace(/(es|s)$/, "");
  const tokens = [...new Set(query.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1).map(stem))];
  const generic = foods.filter((f) => f.kind === "generic").map((f, i) => {
    const words = f.name.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean).map(stem);
    const matched = tokens.filter((t) => words.includes(t)).length;
    const missing = tokens.length - matched;
    const extra = Math.max(0, words.length - matched);
    const plain = words.every((w) => tokens.includes(w) || ["raw", "cooked", "fresh", "plain", "boiled", "grilled", "n", "a", "to", "as", "or"].includes(w)) ? 0 : 1;
    return { f, key: missing * 1000 + plain * 100 + extra * 10 + Math.min(i, 9) / 10 };
  }).sort((a, b) => a.key - b.key).map((x) => x.f);
  const branded = foods.filter((f) => f.kind === "branded");
  // Merge our local hits in front of USDA's live results (dedupe by name), and own the new ones.
  const seen = new Set(local.map((f) => f.name.toLowerCase()));
  const fresh = [...generic.slice(0, 15), ...branded.slice(0, 10)].filter((f) => !seen.has(f.name.toLowerCase()));
  fresh.forEach(cacheFood);
  const ordered = [...local, ...fresh].slice(0, 25);
  foodCache.set(query.toLowerCase(), { at: Date.now(), foods: ordered });
  if (foodCache.size > 500) foodCache.delete(foodCache.keys().next().value);
  return ordered;
}

const barcodeCache = new Map();

function offFood(p, code) {
  const n = p.nutriments ?? {};
  const num = (k) => (typeof n[k] === "number" ? n[k] : Number(n[k]) || 0);
  let kcal = num("energy-kcal_100g");
  if (!kcal && num("energy_100g")) kcal = num("energy_100g") / 4.184;
  const per100 = { kcal, protein: num("proteins_100g"), carbs: num("carbohydrates_100g"), fat: num("fat_100g"),
    fibre: num("fiber_100g"), sugar: num("sugars_100g"),
    sodium: num("sodium_100g") ? num("sodium_100g") * 1000 : num("salt_100g") * 400, satFat: num("saturated-fat_100g") };
  if (!per100.kcal && !per100.protein) return null;
  const servings = [];
  const sg = Number(p.serving_quantity);
  if (sg > 0) servings.push({ label: `${(p.serving_size || "1 serving").trim()} (${Math.round(sg)} g)`, grams: sg });
  const name = (p.product_name_en || p.product_name || "").trim();
  return {
    id: `off:${code}`, name: name || `Product ${code}`, brand: (p.brands || "").split(",")[0].trim() || null,
    kind: "branded", category: null, per100, servings, barcode: code,
  };
}

async function lookupBarcode(raw) {
  const code = String(raw ?? "").replace(/\D/g, "");
  if (code.length < 8 || code.length > 14) throw new HttpError(400, "That doesn't look like a product barcode.");
  const cached = barcodeCache.get(code);
  if (cached && Date.now() - cached.at < FOOD_CACHE_TTL) return cached.food;
  let food = null;
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_en,brands,nutriments,serving_size,serving_quantity`, {
      headers: { "user-agent": "FatLossCoach/1.0 (fatloss-analyzer.fly.dev)" }, signal: AbortSignal.timeout(10_000),
    });
    if (res.ok) { const j = await res.json(); if (j.status === 1 && j.product) food = offFood(j.product, code); }
  } catch (err) { console.warn("openfoodfacts", err.message); }
  if (!food) {
    // USDA Branded carries US GTIN/UPC codes (leading zeros vary, so search both forms).
    try {
      const res = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(USDA_KEY)}`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ query: code, pageSize: 5, dataType: ["Branded"] }), signal: AbortSignal.timeout(10_000),
      });
      if (res.ok) {
        const j = await res.json();
        const hit = (j.foods ?? []).find((f) => String(f.gtinUpc ?? "").replace(/^0+/, "") === code.replace(/^0+/, ""));
        if (hit) food = { ...normaliseFood(hit), barcode: code };
      }
    } catch (err) { console.warn("usda barcode", err.message); }
  }
  if (!food) throw new HttpError(404, "Product not found. Search by name or type it in instead.");
  barcodeCache.set(code, { at: Date.now(), food });
  return food;
}

/** Server-side record of every scan (even ones the user later discards) — the backend's own trend data. */
function logScan({ uid, email, ms, result, ctx, error }) {
  if (!db.enabled) return;
  const row = { uid, email, at: new Date(), ms, model: result?.model ?? MODEL, ok: !error };
  if (result) {
    Object.assign(row, {
      isFood: result.is_food, name: result.meal_name, kcal: result.total_kcal, protein: result.total_protein_g,
      carbs: result.total_carbs_g, fat: result.total_fat_g, confidence: result.confidence, notes: result.notes,
      items: result.items.map((i) => ({ name: i.name, portion: i.portion, grams: i.grams, kcal: i.kcal })),
      tokensIn: result.usage.input, tokensOut: result.usage.output,
    });
  }
  if (ctx?.slot) row.slot = String(ctx.slot);
  if (error) row.error = String(error).slice(0, 200);
  db.add("scans", row).catch((e) => console.error("scan log failed:", e.message));
}

// ---- admin API -------------------------------------------------------------------------------

async function adminUsers() {
  const users = await db.list("users", { fields: ["profile", "goals", "program", "stats", "schema", "updatedAt"] });
  let scans = [];
  try { scans = await db.query("", "scans", { orderBy: { field: "at", direction: "DESCENDING" }, limit: 2000 }); }
  catch (e) { console.error("scans query:", e.message); }
  const byUid = new Map();
  for (const s of scans) {
    const agg = byUid.get(s.uid) ?? { scans: 0, lastScanAt: null, tokensIn: 0, tokensOut: 0 };
    agg.scans += 1;
    agg.lastScanAt = agg.lastScanAt ?? s.at;
    agg.tokensIn += s.tokensIn ?? 0; agg.tokensOut += s.tokensOut ?? 0;
    byUid.set(s.uid, agg);
  }
  return users.map((u) => ({
    uid: u.id, profile: u.profile ?? {}, goals: u.goals ?? {}, program: u.program ?? {}, stats: u.stats ?? {},
    schema: u.schema ?? 1, updatedAt: u.updatedAt, usage: byUid.get(u.id) ?? { scans: 0, lastScanAt: null, tokensIn: 0, tokensOut: 0 },
  }));
}

async function adminUser(uid) {
  if (!/^[A-Za-z0-9]{10,64}$/.test(uid)) throw new HttpError(400, "Bad uid.");
  const [days, meals, scans] = await Promise.all([
    db.list(`users/${uid}/days`, { orderBy: "date", pageSize: 1000 }),
    db.list(`users/${uid}/meals`, { orderBy: "at", pageSize: 1000 }),
    db.query("", "scans", { where: [["uid", "EQUAL", uid]], limit: 1000 }).catch(() => []),
  ]);
  scans.sort((a, b) => (a.at < b.at ? -1 : 1));
  return { uid, days, meals, scans };
}

function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(body), "cache-control": "no-store" });
  res.end(body);
}

function redirect(res, location) {
  res.writeHead(302, { location, "cache-control": "no-store" });
  res.end();
}

// ---- wearable integrations (Whoop / Oura) ---------------------------------------------------

const tokenPath = (uid, vendor) => `users/${uid}/integrations/${vendor}`;

/** Returns a currently-valid access token for (uid, vendor), refreshing if needed. null if not linked. */
async function validAccessToken(uid, vendor) {
  const tok = await db.getDoc(tokenPath(uid, vendor));
  if (!tok?.accessToken) return null;
  if (Date.now() < (tok.expiresAt ?? 0) - 60_000) return tok.accessToken;
  if (!tok.refreshToken) return null;
  const fresh = await wear.refresh(vendor, tok.refreshToken);
  await db.setDoc(tokenPath(uid, vendor), { ...fresh, vendor, linkedAt: tok.linkedAt ?? Date.now(), updatedAt: Date.now() });
  return fresh.accessToken;
}

/** Pull the last `days` of vendor data and normalise it. */
async function wearableSync(uid, vendor, days = 30) {
  const access = await validAccessToken(uid, vendor);
  if (!access) throw new HttpError(409, `${vendor} is not connected.`);
  const since = new Date(Date.now() - days * 86_400_000).toISOString();
  const data = await wear.VENDORS[vendor].pull(access, since);
  await db.setDoc(tokenPath(uid, vendor), { lastSyncAt: Date.now() }).catch(() => {});
  return data;
}

async function handleConnect(req, res, url) {
  // GET /connect/status — which vendors are linked for this user + which are server-configured.
  if (req.method === "GET" && url.pathname === "/connect/status") {
    const { uid } = await verifyUser(req);
    const out = {};
    for (const v of Object.keys(wear.VENDORS)) {
      const configured = wear.vendorConfigured(v);
      const tok = configured && db.enabled ? await db.getDoc(tokenPath(uid, v)).catch(() => null) : null;
      out[v] = { configured, linked: Boolean(tok?.accessToken), lastSyncAt: tok?.lastSyncAt ?? null };
    }
    return send(res, 200, { vendors: out });
  }

  const start = url.pathname.match(/^\/connect\/([a-z]+)\/url$/);
  if (req.method === "GET" && start) {
    const vendor = start[1];
    if (!wear.VENDORS[vendor]) throw new HttpError(404, "Unknown vendor.");
    if (!wear.vendorConfigured(vendor)) throw new HttpError(503, `${vendor} is not configured on the server.`);
    const { uid } = await verifyUser(req);
    const state = await wear.makeState(uid, vendor);
    return send(res, 200, { url: await wear.authorizeUrl(vendor, state) });
  }

  const cb = url.pathname.match(/^\/connect\/([a-z]+)\/callback$/);
  if (req.method === "GET" && cb) {
    const vendor = cb[1];
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    try {
      if (!code || !state) throw new Error("missing code/state");
      const { uid, vendor: sv } = await wear.readState(state);
      if (sv !== vendor) throw new Error("vendor mismatch");
      const tokens = await wear.exchangeCode(vendor, code);
      await db.setDoc(tokenPath(uid, vendor), { ...tokens, vendor, linkedAt: Date.now(), updatedAt: Date.now() });
      return redirect(res, wear.appReturn(vendor, true));
    } catch (e) {
      console.error("connect callback:", e.message);
      return redirect(res, wear.appReturn(vendor, false, e.message));
    }
  }

  const sync = url.pathname.match(/^\/connect\/([a-z]+)\/sync$/);
  if (req.method === "POST" && sync) {
    const vendor = sync[1];
    if (!wear.VENDORS[vendor]) throw new HttpError(404, "Unknown vendor.");
    const { uid } = await verifyUser(req);
    const body = await readJSON(req).catch(() => ({}));
    return send(res, 200, await wearableSync(uid, vendor, body.days ?? 30));
  }

  const unlink = url.pathname.match(/^\/connect\/([a-z]+)\/unlink$/);
  if (req.method === "POST" && unlink) {
    const vendor = unlink[1];
    const { uid } = await verifyUser(req);
    await db.setDoc(tokenPath(uid, vendor), { accessToken: null, refreshToken: null, vendor, unlinkedAt: Date.now() }).catch(() => {});
    return send(res, 200, { ok: true });
  }
  return false;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  try {
    if (req.method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true, model: MODEL, firestore: db.enabled, admin: Boolean(ADMIN_KEY), foods: USDA_KEY !== "DEMO_KEY" ? "usda" : "usda-demo" });

    if (req.method === "GET" && url.pathname === "/barcode") {
      await verifyUser(req);
      return send(res, 200, { food: await lookupBarcode(url.searchParams.get("code")) });
    }

    if (req.method === "GET" && url.pathname === "/foods") {
      await verifyUser(req);
      const foods = await searchFoods(url.searchParams.get("q") ?? "");
      return send(res, 200, { foods });
    }

    if (req.method === "POST" && url.pathname === "/analyze") {
      const { uid, email } = await verifyUser(req);
      const body = await readJSON(req);
      const started = Date.now();
      try {
        const result = await analyze(body);
        const ms = Date.now() - started;
        console.log(JSON.stringify({ uid, ms, kcal: result.total_kcal, model: result.model, usage: result.usage }));
        logScan({ uid, email, ms, result, ctx: body.context });
        return send(res, 200, result);
      } catch (err) {
        logScan({ uid, email, ms: Date.now() - started, ctx: body.context, error: err.message });
        throw err;
      }
    }

    if (req.method === "POST" && url.pathname === "/inbody") {
      const { uid, email } = await verifyUser(req);
      const body = await readJSON(req);
      const started = Date.now();
      try {
        const result = await analyzeBody(body);
        const ms = Date.now() - started;
        console.log(JSON.stringify({ uid, ms, kind: "inbody", weight: result.weight_kg, model: result.model, usage: result.usage }));
        return send(res, 200, result);
      } catch (err) {
        logScan({ uid, email, ms: Date.now() - started, ctx: { mode: "inbody" }, error: err.message });
        throw err;
      }
    }

    if (req.method === "GET" && (url.pathname === "/admin" || url.pathname === "/admin/")) {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" });
      return res.end(ADMIN_HTML);
    }
    if (req.method === "GET" && url.pathname === "/admin/api/users") {
      requireAdmin(req);
      return send(res, 200, { users: await adminUsers(), model: MODEL });
    }
    const m = url.pathname.match(/^\/admin\/api\/users\/([^/]+)$/);
    if (req.method === "GET" && m) {
      requireAdmin(req);
      return send(res, 200, await adminUser(m[1]));
    }

    if (url.pathname.startsWith("/connect/")) {
      const handled = await handleConnect(req, res, url);
      if (handled !== false) return;
    }
    return send(res, 404, { error: "Not found" });
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    if (status >= 500) console.error(err);
    return send(res, status, { error: err.message ?? "Analysis failed." });
  }
});

if (IS_MAIN) {
  server.listen(PORT, "0.0.0.0", () => console.log(`analyzer listening on ${PORT} (model ${MODEL}, firestore ${db.enabled ? "on" : "off"}, admin ${ADMIN_KEY ? "on" : "off"})`));
}

// Exported for unit tests (see tests/micros.test.mjs). No effect on the running server.
export { MealAnalysis, micronutrients, round1 };
