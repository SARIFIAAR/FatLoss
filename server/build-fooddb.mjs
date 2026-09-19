// Builds our own nutrition DB from the full USDA FoodData Central (all public domain):
//   SR Legacy (~7.8k generic) · Foundation (~340) · FNDDS/Survey (~5.4k as-eaten) · Branded (~1.9M, streamed)
//   Output: data/foods.db (SQLite the server queries) + data/core-foods.json (small offline core for the app)
// Branded is 3+ GB so it's streamed with stream-json; the others are small enough to load whole.
import fs from "fs";
import readline from "readline";
import Database from "better-sqlite3";

const DIR = "data";
const N = { kcal: [1008, 2048, 2047], protein: [1003], carbs: [1005], fat: [1004],
           fibre: [1079, 2033], sugar: [2000, 1063], sodium: [1093], satFat: [1258] };
const pick = (m, ids) => { for (const id of ids) if (m[id] != null) return m[id]; return 0; };
const title = (s) => (s || "").toLowerCase().replace(/(^|[\s(/,-])([a-z])/g, (x, p, c) => p + c.toUpperCase());
function nutrients(list) {
  const m = {};
  for (const n of list ?? []) {
    const id = n.nutrient?.id ?? n.nutrientId;
    const amt = n.amount ?? n.value;
    if (id != null && amt != null) m[id] = amt;
  }
  return m;
}

fs.rmSync(`${DIR}/foods.db`, { force: true });
fs.rmSync(`${DIR}/foods.db-wal`, { force: true });
fs.rmSync(`${DIR}/foods.db-shm`, { force: true });
const db = new Database(`${DIR}/foods.db`);
db.pragma("journal_mode = WAL");
db.pragma("synchronous = OFF");
db.exec(`CREATE TABLE foods (
  id TEXT PRIMARY KEY, name TEXT, name_lc TEXT, brand TEXT, kind TEXT, category TEXT,
  kcal REAL, protein REAL, carbs REAL, fat REAL, fibre REAL, sugar REAL, sodium REAL, satFat REAL,
  servings TEXT, barcode TEXT, verified INTEGER DEFAULT 0);`);
const insert = db.prepare(`INSERT OR IGNORE INTO foods
  (id,name,name_lc,brand,kind,category,kcal,protein,carbs,fat,fibre,sugar,sodium,satFat,servings,barcode,verified)
  VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);

let total = 0;
// Branded fallback: many branded items carry only labelNutrients (per serving) — convert to per-100g.
function fromLabel(f) {
  const ln = f.labelNutrients;
  if (!ln || !ln.calories?.value || !(f.servingSize > 0)) return null;
  const unit = (f.servingSizeUnit ?? "g").toLowerCase();
  const grams = unit === "g" || unit === "ml" ? f.servingSize : null;
  if (!grams) return null;
  const k = 100 / grams;
  const v = (x) => (x?.value != null ? x.value * k : 0);
  return { 1008: v(ln.calories), 1003: v(ln.protein), 1005: v(ln.carbohydrates), 1004: v(ln.fat),
           1079: v(ln.fiber), 2000: v(ln.sugars), 1093: v(ln.sodium), 1258: v(ln.saturatedFat) };
}
function add(f, kind, verified) {
  let m = nutrients(f.foodNutrients);
  let kcal = pick(m, N.kcal);
  if (!kcal && kind === "branded") { const lm = fromLabel(f); if (lm) { m = lm; kcal = m[1008]; } }
  if (!kcal) return false;
  const name = title(f.description);
  let servings = [];
  if (kind === "branded" && f.servingSize > 0 && /^(g|grm|ml|mlt)$/i.test(f.servingSizeUnit ?? "")) {
    const lbl = (f.householdServingFullText || "").trim();
    servings = [{ label: lbl ? `${lbl} (${Math.round(f.servingSize)} g)` : `1 serving (${Math.round(f.servingSize)} g)`, grams: f.servingSize }];
  } else {
    servings = (f.foodPortions ?? []).filter((p) => p.gramWeight).slice(0, 6).map((p) => ({
      label: `${[p.amount, p.modifier || p.portionDescription].filter(Boolean).join(" ")} (${Math.round(p.gramWeight)} g)`.trim(), grams: p.gramWeight }));
  }
  const brand = kind === "branded" ? (title(f.brandOwner || f.brandName || "") || null) : null;
  insert.run(`usda-${f.fdcId}`, name, name.toLowerCase(), brand, kind,
    (f.foodCategory?.description ?? f.brandedFoodCategory ?? null),
    kcal, pick(m, N.protein), pick(m, N.carbs), pick(m, N.fat),
    pick(m, N.fibre), pick(m, N.sugar), pick(m, N.sodium), pick(m, N.satFat),
    JSON.stringify(servings), f.gtinUpc ?? null, verified);
  total++;
  return true;
}

// --- small datasets loaded whole ---
function loadWhole(pattern, key, kind, verified) {
  const file = fs.readdirSync(DIR).find((f) => f.includes(pattern) && f.endsWith(".json"));
  if (!file) { console.log(`  (skip ${pattern} — not found)`); return; }
  const arr = JSON.parse(fs.readFileSync(`${DIR}/${file}`, "utf8"))[key];
  const tx = db.transaction((list) => { for (const f of list) add(f, kind, verified); });
  tx(arr);
  console.log(`  ${kind}: ${arr.length} in`);
}
console.log("Importing small datasets…");
loadWhole("sr_legacy", "SRLegacyFoods", "generic", 1);
loadWhole("foundation", "FoundationFoods", "generic", 1);
loadWhole("survey", "SurveyFoods", "generic", 1);
console.log(`  running total: ${total}`);

// --- branded streamed ---
const brandedFile = fs.readdirSync(DIR).find((f) => f.includes("branded") && f.endsWith(".json"));
if (brandedFile) {
  console.log(`Streaming branded (${brandedFile})…`);
  // Branded JSON is one object per line: {"BrandedFoods":[ \n {..}, \n {..} ]}. Read line by line,
  // strip the array wrapper + trailing commas, JSON.parse each — bulletproof and memory-flat.
  let batch = [];
  const flush = db.transaction((list) => { for (const f of list) add(f, "branded", 0); });
  const rl = readline.createInterface({ input: fs.createReadStream(`${DIR}/${brandedFile}`, { encoding: "utf8" }), crlfDelay: Infinity });
  for await (let line of rl) {
    line = line.trim();
    if (line.startsWith('{"BrandedFoods"')) line = line.replace(/^\{"BrandedFoods":\s*\[/, "");
    if (!line.startsWith("{")) continue;
    if (line.endsWith(",")) line = line.slice(0, -1);
    else if (line.endsWith("]}")) line = line.slice(0, -2);
    try { batch.push(JSON.parse(line)); } catch { continue; }
    if (batch.length >= 20000) { flush(batch); batch = []; if (total % 200000 < 20000) console.log(`   …${total}`); }
  }
  if (batch.length) flush(batch);
  console.log(`  branded done`);
}

console.log("Indexing…");
db.exec("CREATE INDEX idx_name_lc ON foods(name_lc); CREATE INDEX idx_barcode ON foods(barcode);");
db.pragma("wal_checkpoint(TRUNCATE)");

// --- compact offline core: everyday generic foods only ---
const COMMON = new Set(["Dairy and Egg Products","Poultry Products","Beef Products","Pork Products",
  "Finfish and Shellfish Products","Fruits and Fruit Juices","Vegetables and Vegetable Products",
  "Legumes and Legume Products","Nut and Seed Products","Cereal Grains and Pasta","Breakfast Cereals",
  "Baked Products","Soups, Sauces, and Gravies","Fats and Oils","Beverages","Sausages and Luncheon Meats"]);
const core = db.prepare("SELECT * FROM foods WHERE kind='generic'").all()
  .filter((r) => COMMON.has(r.category) && r.name.length <= 40 && r.name.split(",").length <= 3)
  .map((r) => ({ id: r.id, name: r.name, kcal: Math.round(r.kcal), protein: +r.protein.toFixed(1),
    carbs: +r.carbs.toFixed(1), fat: +r.fat.toFixed(1), fibre: +r.fibre.toFixed(1),
    sugar: +r.sugar.toFixed(1), sodium: Math.round(r.sodium), satFat: +r.satFat.toFixed(1) }))
  .sort((a, b) => a.name.localeCompare(b.name));
fs.writeFileSync(`${DIR}/core-foods.json`, JSON.stringify(core));

console.log(`\nTOTAL ${total} foods`);
console.log(`  core-foods.json: ${core.length} foods, ${(fs.statSync(`${DIR}/core-foods.json`).size/1024).toFixed(0)} KB`);
console.log(`  foods.db: ${(fs.statSync(`${DIR}/foods.db`).size/1024/1024).toFixed(0)} MB`);
db.close();
