// bulk_import_usda.mjs — USDA FoodData Central BRANDED follow-up to the OFF import.
//
// Mirrors scripts/bulk_import_foods.mjs exactly, but sources from the FDC *paginated Search API*
// (NOT the bulk CSV/ZIP — full-dataset pulls die in this environment: memory kills + the ~40-min
// background-task limit). Adds US branded foods OFF didn't cover into a COPY of the CURRENT live
// DB. Rows are byte-compatible with server.js (id `usda:<fdcId>`, per-100g, kind branded, verified 0),
// reusing the server's nutrient-id map + normaliseFood()/build-fooddb.mjs conventions.
//
// SAFE: works on data/foods.db.bulk (fresh VACUUM-INTO copy of data/foods.db). Never mutates the
// live DB. No deploy, no push. Dedupes barcode + name/brand against existing rows (OFF already
// added many branded — high dupe overlap is expected and fine) and within the batch.
//
// Run:  USDA_API_KEY=<key> node scripts/bulk_import_usda.mjs
//   (or the key is read from scripts/../<scratch>/.usda_key if USDA_API_KEY is unset)

import fs from "fs";
import path from "path";
import Database from "better-sqlite3";

const SERVER_DIR = path.resolve(new URL("..", import.meta.url).pathname);
const DATA_DIR = path.join(SERVER_DIR, "data");
const LIVE_DB = path.join(DATA_DIR, "foods.db");
const COPY_DB = path.join(DATA_DIR, "foods.db.bulk");

const USDA_KEY = process.env.USDA_API_KEY ||
  (() => { try { return fs.readFileSync(path.join(process.env.KEY_FILE || "/dev/null"), "utf8").trim(); } catch { return ""; } })();
if (!USDA_KEY || USDA_KEY === "DEMO_KEY") {
  console.error("FATAL: no real USDA_API_KEY (DEMO_KEY is 30 req/hr — refuse to run a broad seed on it). Set USDA_API_KEY or KEY_FILE.");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Nutrient IDs + normalisation — copied verbatim from server.js / build-fooddb.mjs so rows match.
// ---------------------------------------------------------------------------
const NUTRIENT = { kcal: [1008, 2048, 2047], protein: [1003], carbs: [1005], fat: [1004],
                   fibre: [1079, 2033], sugar: [2000, 1063], sodium: [1093], satFat: [1258] };

/** amount for the first present nutrient id, from a search-result foodNutrients array. */
function nutrient(list, ids) {
  for (const id of ids) {
    const hit = (list || []).find((n) => (n.nutrientId ?? n.nutrient?.id) === id);
    const val = hit ? (hit.value ?? hit.amount) : undefined;
    if (typeof val === "number") return val;
  }
  return 0;
}
function titleCase(str) {
  return (str || "").toLowerCase().replace(/(^|[\s(/,-])([a-z])/g, (m, pre, c) => pre + c.toUpperCase());
}

/** Branded search-result item -> normalised food (per-100g). Search API nutrients are already
 *  per-100g; if a branded item carries only labelNutrients (per serving), convert per build-fooddb. */
function normaliseUsda(f) {
  const list = f.foodNutrients || [];
  let per100 = {
    kcal: nutrient(list, NUTRIENT.kcal), protein: nutrient(list, NUTRIENT.protein),
    carbs: nutrient(list, NUTRIENT.carbs), fat: nutrient(list, NUTRIENT.fat),
    fibre: nutrient(list, NUTRIENT.fibre), sugar: nutrient(list, NUTRIENT.sugar),
    sodium: nutrient(list, NUTRIENT.sodium), satFat: nutrient(list, NUTRIENT.satFat),
  };
  // labelNutrients fallback (per-serving -> per-100g) when foodNutrients has no kcal.
  if (!per100.kcal && f.labelNutrients && f.labelNutrients.calories?.value && f.servingSize > 0) {
    const unit = (f.servingSizeUnit || "g").toLowerCase();
    const grams = unit === "g" || unit === "grm" || unit === "ml" || unit === "mlt" ? f.servingSize : null;
    if (grams) {
      const k = 100 / grams; const v = (x) => (x?.value != null ? x.value * k : 0);
      const ln = f.labelNutrients;
      per100 = { kcal: v(ln.calories), protein: v(ln.protein), carbs: v(ln.carbohydrates), fat: v(ln.fat),
        fibre: v(ln.fiber), sugar: v(ln.sugars), sodium: v(ln.sodium), satFat: v(ln.saturatedFat) };
    }
  }
  const servings = [];
  if (f.servingSize > 0 && /^(g|grm|ml|mlt)$/i.test(f.servingSizeUnit || "")) {
    const label = (f.householdServingFullText || "").trim();
    servings.push({ label: label ? `${label} (${Math.round(f.servingSize)} g)` : `1 serving (${Math.round(f.servingSize)} g)`, grams: f.servingSize });
  }
  return {
    id: `usda:${f.fdcId}`,
    name: titleCase(f.description),
    brand: titleCase(f.brandOwner || f.brandName || "") || null,
    kind: "branded",
    category: f.brandedFoodCategory || f.foodCategory || null,
    per100, servings,
    barcode: (f.gtinUpc && String(f.gtinUpc).replace(/\D/g, "")) || null,
  };
}

/** name+brand dedupe key. IDENTICAL to server.js foodKey(). */
function foodKey(f) {
  return `${(f.name || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()}|${(f.brand || "").toLowerCase().trim()}`;
}

/** Quality gate: real name + complete core macros per-100g (kcal + protein+carbs+fat present). */
function passesQuality(f) {
  if (!f) return false;
  const name = (f.name || "").trim();
  if (name.length < 2) return false;
  const p = f.per100;
  const num = (v) => typeof v === "number" && Number.isFinite(v);
  // kcal must be positive; protein/carbs/fat must be present (numbers; 0 is a valid macro value here
  // only if the other signals hold — but require kcal>0 AND all three macros numeric).
  return p.kcal > 0 && num(p.protein) && num(p.carbs) && num(p.fat);
}

// ---------------------------------------------------------------------------
// Seed list — FDC Search caps pageNumber*pageSize ≈ 10k per query, so we iterate many seeds for
// broad branded coverage: beverages OFF missed + snacks/cereal/dairy/frozen/condiments + big US brands.
// ---------------------------------------------------------------------------
const SEEDS = (process.env.USDA_SEEDS || [
  // beverages (mirror OFF terms)
  "soda", "cola", "energy drink", "sports drink", "juice", "beer", "wine", "water", "iced tea", "kombucha",
  // snacks
  "chips", "crackers", "protein bar", "granola bar", "cookies", "candy", "chocolate", "popcorn", "pretzels", "nuts",
  // breakfast/cereal
  "cereal", "oatmeal", "granola", "pancake", "waffle",
  // dairy
  "yogurt", "cheese", "milk", "butter", "cream cheese", "ice cream",
  // frozen / meals
  "frozen pizza", "frozen meal", "chicken nuggets", "burrito", "fries",
  // condiments / pantry
  "ketchup", "mustard", "mayonnaise", "salad dressing", "pasta sauce", "peanut butter", "jam", "syrup", "bread", "tortilla",
  "rice", "pasta", "soup", "beans", "canned tomatoes",
  // big US brands OFF often lacks
  "Quest", "Chobani", "Kirkland", "Trader Joe", "Gatorade", "Cheerios", "Doritos", "Oreo", "Kellogg", "Kraft",
  "Campbell", "Nature Valley", "Clif", "Pop-Tarts", "Hershey", "Lay's", "Pringles", "Ben & Jerry", "Haagen-Dazs",
].join("|")).split("|").map((s) => s.trim()).filter(Boolean);

const PAGE_SIZE = 200;
const MAX_PAGES_PER_SEED = Number(process.env.USDA_MAX_PAGES || 5); // 5*200 = 1000 hits/seed cap
const MAX_TOTAL_ROWS = 3_700_000;                                    // ~1.5 GB size cap (same as OFF)
const COMMIT_EVERY = 5_000;
// Rate limit: FDC allows ~1000 req/hr => min 3.6s between calls. Use 4s to stay comfortably under.
const REQ_DELAY_MS = Number(process.env.USDA_REQ_DELAY_MS || 4000);
const REQ_RETRIES = 5;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchSearch(query, pageNumber) {
  const url = `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(USDA_KEY)}` +
    `&dataType=Branded&pageSize=${PAGE_SIZE}&pageNumber=${pageNumber}&query=${encodeURIComponent(query)}`;
  let lastErr;
  for (let attempt = 1; attempt <= REQ_RETRIES; attempt++) {
    try {
      const res = await fetch(url, { headers: { accept: "application/json" }, signal: AbortSignal.timeout(30_000) });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      return { foods: Array.isArray(json.foods) ? json.foods : [], totalHits: Number(json.totalHits) || 0 };
    } catch (e) {
      lastErr = e;
      if (attempt < REQ_RETRIES) await sleep(2000 * attempt * attempt); // 2s,8s,18s,32s backoff
    }
  }
  throw lastErr;
}

// ---------------------------------------------------------------------------
async function main() {
  const t0 = Date.now();
  if (!fs.existsSync(LIVE_DB)) throw new Error(`live DB not found at ${LIVE_DB}`);

  // 1) Fresh VACUUM-INTO copy of the CURRENT live DB (the imported 442k-row one).
  console.log("Copying live DB -> bulk copy (VACUUM INTO)…");
  fs.rmSync(COPY_DB, { force: true }); fs.rmSync(`${COPY_DB}-wal`, { force: true }); fs.rmSync(`${COPY_DB}-shm`, { force: true });
  { const src = new Database(LIVE_DB, { readonly: true }); src.exec(`VACUUM INTO '${COPY_DB.replace(/'/g, "''")}'`); src.close(); }

  const db = new Database(COPY_DB);
  db.pragma("journal_mode = WAL"); db.pragma("synchronous = OFF");
  const startRows = db.prepare("SELECT COUNT(*) c FROM foods").get().c;
  console.log(`Copy opened: ${startRows.toLocaleString()} rows.`);

  // 2) Dedupe sets (existing rows win).
  console.log("Loading existing barcodes + name/brand keys…");
  const seenBarcode = new Set(), seenKey = new Set();
  for (const r of db.prepare("SELECT name, brand, barcode FROM foods").all()) {
    if (r.barcode) seenBarcode.add(String(r.barcode));
    seenKey.add(foodKey({ name: r.name, brand: r.brand }));
  }
  console.log(`  ${seenBarcode.size.toLocaleString()} barcodes, ${seenKey.size.toLocaleString()} name/brand keys.`);

  // 3) Prepared INSERT — EXACT column mapping as server.js cacheFood(), verified=0.
  const insert = db.prepare(`INSERT OR IGNORE INTO foods
    (id,name,name_lc,brand,kind,category,kcal,protein,carbs,fat,fibre,sugar,sodium,satFat,servings,barcode,verified)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)`);
  const insertBatch = db.transaction((batch) => {
    for (const f of batch) {
      insert.run(f.id ?? `usda-${f.barcode}`, f.name, (f.name || "").toLowerCase(), f.brand ?? null, f.kind ?? "branded", f.category ?? null,
        f.per100.kcal || 0, f.per100.protein || 0, f.per100.carbs || 0, f.per100.fat || 0,
        f.per100.fibre || 0, f.per100.sugar || 0, f.per100.sodium || 0, f.per100.satFat || 0,
        JSON.stringify(f.servings ?? []), f.barcode ?? null);
    }
  });

  // 4) Iterate seeds; paginate each; normalise -> quality -> dedupe -> batch insert.
  let curRows = startRows, capped = false, reqCount = 0;
  let totalScanned = 0, totalAdded = 0, totalLowQ = 0, totalDupe = 0, totalNoName = 0;
  const perSeed = {};

  for (const seed of SEEDS) {
    if (capped) break;
    let added = 0, scanned = 0, page = 1, hitEnd = false;
    let batch = [];
    const flush = () => { if (batch.length) { insertBatch(batch); batch = []; } };

    while (page <= MAX_PAGES_PER_SEED && !capped && !hitEnd) {
      let res;
      try { res = await fetchSearch(seed, page); reqCount++; }
      catch (e) { console.warn(`  [${seed}] page ${page} failed after retries (${e.message}) — stopping this seed.`); break; }
      if (res.foods.length === 0) break;

      for (const raw of res.foods) {
        scanned++; totalScanned++;
        const f = normaliseUsda(raw);
        if (!f.name || f.name.length < 2) { totalNoName++; continue; }
        if (!passesQuality(f)) { totalLowQ++; continue; }
        if (f.barcode && seenBarcode.has(String(f.barcode))) { totalDupe++; continue; }
        const k = foodKey(f);
        if (seenKey.has(k)) { totalDupe++; continue; }
        if (f.barcode) seenBarcode.add(String(f.barcode));
        seenKey.add(k);
        batch.push(f); added++; totalAdded++; curRows++;
        if (curRows >= MAX_TOTAL_ROWS) { capped = true; break; }
        if (batch.length >= COMMIT_EVERY) flush();
      }
      flush();
      if (res.foods.length < PAGE_SIZE) hitEnd = true; // exhausted this seed
      page++;
      await sleep(REQ_DELAY_MS);
    }
    flush();
    perSeed[seed] = { added, scanned };
    console.log(`  [${seed}] scanned ${scanned}, added ${added}` + (capped ? " (ROW CAP HIT)" : ""));
  }

  if (capped) console.log(`  NOTE: hit row cap (${MAX_TOTAL_ROWS.toLocaleString()}).`);

  // 5) Indexes + checkpoint.
  console.log("Verifying / rebuilding indexes…");
  const idx = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='index'").all().map((r) => r.name));
  if (!idx.has("idx_name_lc")) db.exec("CREATE INDEX idx_name_lc ON foods(name_lc)");
  if (!idx.has("idx_barcode")) db.exec("CREATE INDEX idx_barcode ON foods(barcode)");
  db.pragma("wal_checkpoint(TRUNCATE)");
  const finalRows = db.prepare("SELECT COUNT(*) c FROM foods").get().c;
  db.close();

  const bytes = fs.statSync(COPY_DB).size;
  const mins = ((Date.now() - t0) / 60000).toFixed(1);

  console.log("\n================= USDA BRANDED IMPORT SUMMARY =================");
  console.log(`  copy:            ${COPY_DB}`);
  console.log(`  final size:      ${(bytes / 1e6).toFixed(1)} MB (${(bytes / 1e9).toFixed(2)} GB)`);
  console.log(`  rows before:     ${startRows.toLocaleString()}`);
  console.log(`  rows after:      ${finalRows.toLocaleString()}`);
  console.log(`  added (USDA):    ${totalAdded.toLocaleString()}`);
  console.log(`  products scanned: ${totalScanned.toLocaleString()}`);
  console.log(`  API requests:    ${reqCount}  (~${REQ_DELAY_MS}ms apart; limit ~1000/hr)`);
  console.log(`  skipped — no name:         ${totalNoName.toLocaleString()}`);
  console.log(`  skipped — low quality:     ${totalLowQ.toLocaleString()}`);
  console.log(`  skipped — dupe (barcode/name+brand): ${totalDupe.toLocaleString()}`);
  console.log(`  capped:          ${capped ? "YES" : "no"}`);
  console.log(`  elapsed:         ${mins} min`);
  console.log("  per-seed added:");
  for (const [s, v] of Object.entries(perSeed)) console.log(`    ${s.padEnd(20)} added ${String(v.added).padStart(5)}  (scanned ${v.scanned})`);
  if (bytes > 1.5e9) console.log("  WARNING: final size exceeds 1.5 GB — review before swapping.");
  console.log("==============================================================");
}

main().catch((e) => { console.error("\nUSDA IMPORT FAILED:", e); process.exitCode = 1; });
