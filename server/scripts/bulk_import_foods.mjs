// bulk_import_foods.mjs — ONE-TIME bulk expansion of the offline food DB.
//
// Imports branded/packaged foods from the Open Food Facts full export into a COPY of
// data/foods.db, so branded names (a beer brand, sodas, snacks) are findable offline without
// depending on the live OFF API (which intermittently rate-limits / load-sheds).
//
// PIPELINE (two stages; this file is stage 2):
//   Stage 1 (scripts/extract_off.py, DuckDB): reads the OFF Parquet export, projects only the
//     needed columns, applies the quality filter, reproduces offFood()'s per-100g math, and
//     writes a compact JSONL (one product/row per line: code,name,brand,serving_*,macros).
//     Why DuckDB+Parquet: the 12 GB OFF JSONL dump throttles hard and can't be streamed reliably;
//     the 7.85 GB Parquet is columnar, so extracting ~10 columns is far cheaper. See NOTES below.
//   Stage 2 (THIS script, better-sqlite3): reads that JSONL, re-normalises to the EXACT
//     server.js cacheFood() shape (id `off:<code>`, name_lc, servings JSON), dedupes against the
//     DB copy (existing rows win) and within the batch, and bulk-inserts in batched transactions.
//
// SAFE BY DESIGN:
//   - Works on data/foods.db.bulk (a fresh VACUUM-INTO copy). Never mutates the live data/foods.db.
//   - Dedupes against existing rows (barcode OR name+brand key) — existing curated rows win.
//   - Single prepared INSERT OR IGNORE in batched transactions; progress every ~100k rows.
//   - Caps total DB rows to stay under the size budget.
//
// Run:
//   1. python3 scripts/extract_off.py <scratch>/off_extract.jsonl [<local food.parquet>]
//   2. OFF_EXTRACT=<scratch>/off_extract.jsonl node scripts/bulk_import_foods.mjs
// Then the CEO reviews size and approves the swap (data/foods.db.bulk -> data/foods.db) + redeploy.
//
// Column mapping / id / name_lc / foodKey / offFood normalisation are copied verbatim from
// server.js so imported rows are byte-compatible with rows the live server caches.

import fs from "fs";
import path from "path";
import os from "os";
import readline from "readline";
import Database from "better-sqlite3";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const SERVER_DIR = path.resolve(new URL("..", import.meta.url).pathname); // server/
const DATA_DIR = path.join(SERVER_DIR, "data");
const LIVE_DB = path.join(DATA_DIR, "foods.db");
const COPY_DB = path.join(DATA_DIR, "foods.db.bulk");

// Stage-1 output consumed here: one JSON object per line (see extract_off.py SELECT columns).
const OFF_EXTRACT = process.env.OFF_EXTRACT ||
  path.join(process.env.BULK_SCRATCH || path.join(os.tmpdir(), "foodbulk"), "off_extract.jsonl");

// Size budget: stop importing once the DB would blow past ~1.5 GB. A generic row is a few
// hundred bytes; 160 MB / 439,697 ≈ 365 B/row, so ~1.4 GB total ≈ ~3.8M rows. Cap total rows
// (existing + newly added) so the resulting .db stays comfortably under ~1.5 GB.
const MAX_TOTAL_ROWS = 3_700_000;   // hard cap on total rows in the DB after import
const COMMIT_EVERY = 50_000;        // rows per transaction
const PROGRESS_EVERY = 100_000;     // extract lines scanned between progress prints

// ---------------------------------------------------------------------------
// Normalisation — copied verbatim from server.js (offFood + foodKey)
// ---------------------------------------------------------------------------

/** OFF product -> our normalised food shape. IDENTICAL to server.js offFood(). */
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

/** name+brand dedupe key. IDENTICAL to server.js foodKey(). */
function foodKey(f) {
  return `${(f.name || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()}|${(f.brand || "").toLowerCase().trim()}`;
}

// ---------------------------------------------------------------------------
// Quality gate — task spec: real product name AND complete core macros per 100 g
// (kcal present, and at least protein+carbs+fat present). Unknown micros stay null.
// offFood already stores 0 for absent nutriments; we require the four core macros to be
// meaningfully present (> 0 or explicitly numeric) so we don't import empty/junk rows.
// ---------------------------------------------------------------------------
function passesQuality(f, rawProduct) {
  if (!f) return false;
  // Real product name (offFood falls back to "Product <code>" when there's none — reject those).
  const name = (f.name || "").trim();
  if (!name || /^Product \d+$/.test(name)) return false;
  if (name.length < 2) return false;
  // Core macros must be present per 100 g. OFF stores them as *_100g; require the raw fields to
  // exist (present, not merely coerced to 0), and kcal to be a real positive value.
  const n = rawProduct.nutriments ?? {};
  const has = (k) => n[k] != null && n[k] !== "" && Number.isFinite(Number(n[k]));
  const kcalPresent = f.per100.kcal > 0;
  const proteinPresent = has("proteins_100g");
  const carbsPresent = has("carbohydrates_100g");
  const fatPresent = has("fat_100g");
  return kcalPresent && proteinPresent && carbsPresent && fatPresent;
}

// ---------------------------------------------------------------------------
// Targeted paginated fetch from the OFF Search API (v2). The full-dump approaches (12 GB JSONL,
// 7.85 GB Parquet) proved unusable in this environment: remote egress throttles hard and the
// large in-memory/columnar passes get OS-killed under memory pressure. Instead we import only the
// categories the user actually cares about (branded beverages / alcohol is the known offline gap)
// via MANY SMALL paginated calls — memory-light (one page in flight, then discarded) and resilient
// (per-page retry, backoff, and OFF's occasional 200-HTML load-shed is retried, not parsed).
// ---------------------------------------------------------------------------
const UA = "FatLossCoach-bulk-import/1.0 (fatloss-analyzer.fly.dev; contact metatec.dubai@gmail.com)";

// Target categories (OFF `categories_tags_en` slugs). The gap the user hit is branded drinks.
const CATEGORIES = (process.env.OFF_CATEGORIES || [
  "beers", "wines", "spirits", "alcoholic-beverages",
  "carbonated-drinks", "sodas", "energy-drinks", "sports-drinks",
  "waters", "fruit-juices",
].join(",")).split(",").map((s) => s.trim()).filter(Boolean);

const PAGE_SIZE = 100;
const MAX_PAGES_PER_CAT = Number(process.env.OFF_MAX_PAGES || 300);   // ~30k products/category cap
const PAGE_DELAY_MS = Number(process.env.OFF_PAGE_DELAY_MS || 400);   // politeness between pages
const PAGE_RETRIES = 4;                                               // per-page retry budget
const FIELDS = "code,product_name,product_name_en,brands,serving_size,serving_quantity,nutriments";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Fetch one OFF search page. Returns { products, count } or throws after exhausting retries.
 *  Handles OFF's occasional 200-with-HTML load-shed (non-JSON) by treating it as retryable. */
async function fetchPage(category, page) {
  const url = `https://world.openfoodfacts.org/api/v2/search?` +
    `categories_tags_en=${encodeURIComponent(category)}` +
    `&fields=${FIELDS}&page_size=${PAGE_SIZE}&page=${page}`;
  let lastErr;
  for (let attempt = 1; attempt <= PAGE_RETRIES; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { "user-agent": UA, accept: "application/json" },
        signal: AbortSignal.timeout(30_000),
      });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      // OFF sometimes load-sheds with a 200 HTML interstitial — retry rather than parse garbage.
      if (!/json/i.test(res.headers.get("content-type") || "")) throw new Error("non-JSON (load-shed)");
      const json = await res.json();
      return { products: Array.isArray(json.products) ? json.products : [], count: Number(json.count) || 0 };
    } catch (e) {
      lastErr = e;
      if (attempt < PAGE_RETRIES) await sleep(1000 * attempt * attempt); // 1s,4s,9s backoff
    }
  }
  throw lastErr;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const t0 = Date.now();

  if (!fs.existsSync(LIVE_DB)) throw new Error(`live DB not found at ${LIVE_DB}`);

  // 1) Make a clean COPY of the live DB. Use SQLite's own backup (VACUUM INTO) so a live WAL is
  //    checkpointed into a single consistent file — never a raw cp of a file with a hot -wal.
  console.log("Copying live DB -> bulk copy (VACUUM INTO, consistent snapshot)…");
  fs.rmSync(COPY_DB, { force: true });
  fs.rmSync(`${COPY_DB}-wal`, { force: true });
  fs.rmSync(`${COPY_DB}-shm`, { force: true });
  {
    const src = new Database(LIVE_DB, { readonly: true });
    src.exec(`VACUUM INTO '${COPY_DB.replace(/'/g, "''")}'`);
    src.close();
  }

  const db = new Database(COPY_DB);
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = OFF");

  const startRows = db.prepare("SELECT COUNT(*) c FROM foods").get().c;
  console.log(`Copy opened: ${startRows.toLocaleString()} rows.`);

  // 2) Preload dedupe sets from the copy (existing rows win).
  console.log("Loading existing barcodes + name/brand keys for dedupe…");
  const seenBarcode = new Set();
  const seenKey = new Set();
  {
    const rows = db.prepare("SELECT name, brand, barcode FROM foods").all();
    for (const r of rows) {
      if (r.barcode) seenBarcode.add(String(r.barcode));
      seenKey.add(foodKey({ name: r.name, brand: r.brand }));
    }
  }
  console.log(`  ${seenBarcode.size.toLocaleString()} barcodes, ${seenKey.size.toLocaleString()} name/brand keys.`);

  // 3) Prepared INSERT — EXACT column order/mapping as server.js cacheFood(), verified=0.
  const insert = db.prepare(`INSERT OR IGNORE INTO foods
    (id,name,name_lc,brand,kind,category,kcal,protein,carbs,fat,fibre,sugar,sodium,satFat,servings,barcode,verified)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)`);
  const insertBatch = db.transaction((batch) => {
    for (const f of batch) {
      insert.run(
        f.id ?? `off-${f.barcode}`, f.name, (f.name || "").toLowerCase(), f.brand ?? null, f.kind ?? "branded", f.category ?? null,
        f.per100.kcal || 0, f.per100.protein || 0, f.per100.carbs || 0, f.per100.fat || 0,
        f.per100.fibre || 0, f.per100.sugar || 0, f.per100.sodium || 0, f.per100.satFat || 0,
        JSON.stringify(f.servings ?? []), f.barcode ?? null);
    }
  });

  // 4) Page each category: fetch -> normalise -> quality gate -> dedupe -> batch insert -> discard.
  let curRows = startRows, capped = false;
  let totalScanned = 0, totalAdded = 0, totalLowQ = 0, totalDupe = 0, totalNoCode = 0;
  const perCat = {};

  for (const category of CATEGORIES) {
    if (capped) break;
    let added = 0, scanned = 0, page = 1, pages = 0;
    let batch = [];
    const flush = () => { if (batch.length) { insertBatch(batch); batch = []; } };

    while (page <= MAX_PAGES_PER_CAT && !capped) {
      let res;
      try {
        res = await fetchPage(category, page);
      } catch (e) {
        console.warn(`  [${category}] page ${page} failed after retries (${e.message}) — stopping this category.`);
        break;
      }
      pages = page;
      if (res.products.length === 0) break; // exhausted

      for (const p of res.products) {
        scanned++; totalScanned++;
        const code = p.code != null ? String(p.code).trim() : "";
        if (!code) { totalNoCode++; continue; }
        const f = offFood(p, code);
        if (!passesQuality(f, p)) { totalLowQ++; continue; }
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

      // Reached the end of results for this category?
      if (res.products.length < PAGE_SIZE) break;
      page++;
      await sleep(PAGE_DELAY_MS);
    }
    flush();
    perCat[category] = { added, scanned, pages };
    console.log(`  [${category}] ${pages} page(s), scanned ${scanned}, added ${added}` + (capped ? " (ROW CAP HIT)" : ""));
  }

  if (capped) console.log(`  NOTE: hit row cap (${MAX_TOTAL_ROWS.toLocaleString()}).`);

  // 5) Ensure indexes intact (VACUUM INTO carries them; assert + recreate if absent).
  console.log("Verifying / rebuilding indexes…");
  const idxNames = new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='index'").all().map((r) => r.name));
  if (!idxNames.has("idx_name_lc")) db.exec("CREATE INDEX idx_name_lc ON foods(name_lc)");
  if (!idxNames.has("idx_barcode")) db.exec("CREATE INDEX idx_barcode ON foods(barcode)");
  db.pragma("wal_checkpoint(TRUNCATE)");

  const finalRows = db.prepare("SELECT COUNT(*) c FROM foods").get().c;
  db.close();

  const bytes = fs.statSync(COPY_DB).size;
  const mins = ((Date.now() - t0) / 60000).toFixed(1);

  console.log("\n===================== BULK IMPORT SUMMARY =====================");
  console.log(`  copy:            ${COPY_DB}`);
  console.log(`  final size:      ${(bytes / 1e6).toFixed(1)} MB (${(bytes / 1e9).toFixed(2)} GB)`);
  console.log(`  rows before:     ${startRows.toLocaleString()}`);
  console.log(`  rows after:      ${finalRows.toLocaleString()}`);
  console.log(`  added (OFF):     ${totalAdded.toLocaleString()}`);
  console.log(`  products scanned: ${totalScanned.toLocaleString()}`);
  console.log(`  skipped — no barcode:      ${totalNoCode.toLocaleString()}`);
  console.log(`  skipped — low quality:     ${totalLowQ.toLocaleString()}`);
  console.log(`  skipped — dupe (barcode/name+brand): ${totalDupe.toLocaleString()}`);
  console.log(`  capped:          ${capped ? "YES (hit MAX_TOTAL_ROWS)" : "no"}`);
  console.log(`  elapsed:         ${mins} min`);
  console.log("  per-category added:");
  for (const [c, s] of Object.entries(perCat)) console.log(`    ${c.padEnd(22)} added ${String(s.added).padStart(6)}  (scanned ${s.scanned}, ${s.pages} pages)`);
  if (bytes > 1.5e9) console.log("  WARNING: final size exceeds 1.5 GB — review before swapping.");
  console.log("================================================================");
}

main().catch((e) => { console.error("\nBULK IMPORT FAILED:", e); process.exitCode = 1; });
