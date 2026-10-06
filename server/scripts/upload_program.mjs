// upload_program.mjs — FatLoss Coach / HUMANS meal-program content uploader (Admin SDK).
//
// Publishes a MEAL PROGRAM + its RECIPES to Firestore and uploads their images to Storage, so the
// team can add/edit programs & recipes WITHOUT an app build. The dietitian has NO Firebase access:
// content ships via this script run with the admin service-account key. The Admin SDK bypasses
// security rules, so clients stay read-only (see firestore.rules / storage.rules).
//
// ---------------------------------------------------------------------------------------------
// WHAT IT DOES (idempotent upsert by id — safe to re-run; re-running updates in place)
//   1. Uploads the banner image to  content/programs/<programId>/banner.<ext>            (public)
//   2. Uploads each recipe image to content/programs/<programId>/recipes/<recipeId>.<ext> (public)
//   3. Writes  mealPrograms/<programId>                 with the banner's public URL
//   4. Writes  mealPrograms/<programId>/recipes/<recipeId>  with each recipe's public URL
//   Images are made publicly readable; the stored URL is the token-free download form:
//     https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<url-encoded-path>?alt=media
//
// ---------------------------------------------------------------------------------------------
// INPUT JSON FORMAT (one program per file). Image paths are resolved relative to the JSON file's
// directory (or absolute). Fields map 1:1 to the iOS read schema — do not rename.
//
// {
//   "programId": "ariana",                       // Firestore doc id under mealPrograms/
//   "name": "The Ariana Program",                // string
//   "blurb": "Whole-food porridge & overnight-oat bowls.",  // string
//   "bannerImage": "photos/ariana-program-banner.jpg",      // local path -> content/programs/<id>/banner.<ext>
//   "order": 1,                                  // int (program sort order)
//   "published": true,                           // bool
//   "recipes": [
//     {
//       "recipeId": "ariana-b01",                // doc id under .../recipes/
//       "title": "Golden Turmeric Porridge",     // string
//       "category": "breakfast",                 // "breakfast" | "lunch" | "dinner"
//       "image": "photos/ariana-01-studio.jpg",  // local path -> content/programs/<id>/recipes/<recipeId>.<ext>
//       "serves": 1,                             // int
//       "timeMin": 11,                           // int (total prep+cook minutes)
//       "type": "Hot porridge",                  // string (free-form, e.g. "Overnight oats")
//       "ingredients": ["50 g rolled oats", "..."],          // [string]
//       "method": ["Simmer oats and milk 5-6 min...", "..."],// [string]
//       "nutrition": { "kcal": 455, "protein": 14, "carbs": 55, "fat": 20, "fibre": 9, "sugar": 20 }, // all numbers
//       "note": "Assumes semi-skimmed milk; honey not counted.",  // string
//       "order": 1,                              // int (recipe sort order within the program)
//       "published": true                        // bool
//     }
//   ]
// }
//
// updatedAt is stamped by the server on every write (FieldValue.serverTimestamp()).
//
// ---------------------------------------------------------------------------------------------
// USAGE
//   GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/fat-loss-6516d-firebase-adminsdk-fbsvc-a041340c2a.json \
//     node server/scripts/upload_program.mjs <program.json>
//   # or pass the key explicitly:
//   node server/scripts/upload_program.mjs <program.json> --key <path-to-service-account.json>
//   # dry run (validate + log, no writes/uploads):
//   node server/scripts/upload_program.mjs <program.json> --dry-run
//
// Project: fat-loss-6516d  ·  Bucket: fat-loss-6516d.firebasestorage.app (Blaze).
// NEVER commit the service-account key (it is git-ignored).

import fs from "fs";
import path from "path";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

const BUCKET = "fat-loss-6516d.firebasestorage.app";
const PROJECT_ID = "fat-loss-6516d";

const EXT_CONTENT_TYPE = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp",
};

// ---- args ------------------------------------------------------------------------------------
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const keyIdx = args.indexOf("--key");
const keyPath = keyIdx >= 0 ? args[keyIdx + 1] : process.env.GOOGLE_APPLICATION_CREDENTIALS;
const jsonArg = args.find((a) => !a.startsWith("--") && a !== keyPath);

function die(msg) { console.error(`\n  FATAL: ${msg}\n`); process.exit(1); }
function log(msg) { console.log(msg); }

if (!jsonArg) die("no program JSON given.  Usage: node upload_program.mjs <program.json> [--key <key.json>] [--dry-run]");

const jsonPath = path.resolve(jsonArg);
if (!fs.existsSync(jsonPath)) die(`program JSON not found: ${jsonPath}`);
const baseDir = path.dirname(jsonPath);

let program;
try { program = JSON.parse(fs.readFileSync(jsonPath, "utf8")); }
catch (e) { die(`program JSON is not valid JSON: ${e.message}`); }

// ---- validation (fail fast, before any write) ------------------------------------------------
const CATEGORIES = new Set(["breakfast", "lunch", "dinner"]);
const errors = [];
function req(cond, msg) { if (!cond) errors.push(msg); }

req(typeof program.programId === "string" && program.programId.length, "programId must be a non-empty string");
req(typeof program.name === "string", "name must be a string");
req(typeof program.blurb === "string", "blurb must be a string");
req(typeof program.bannerImage === "string" && program.bannerImage.length, "bannerImage (local path) is required");
req(Number.isInteger(program.order), "order must be an int");
req(typeof program.published === "boolean", "published must be a bool");
req(Array.isArray(program.recipes) && program.recipes.length, "recipes must be a non-empty array");

function resolveImg(p, label) {
  const abs = path.isAbsolute(p) ? p : path.resolve(baseDir, p);
  if (!fs.existsSync(abs)) errors.push(`${label}: image not found: ${abs}`);
  const ext = path.extname(abs).toLowerCase();
  if (!EXT_CONTENT_TYPE[ext]) errors.push(`${label}: unsupported image type '${ext}' (jpg/jpeg/png/webp)`);
  return { abs, ext };
}

const banner = typeof program.bannerImage === "string" ? resolveImg(program.bannerImage, "banner") : null;

const seenRecipeIds = new Set();
(program.recipes || []).forEach((r, i) => {
  const tag = `recipe[${i}] (${r.recipeId || "?"})`;
  req(typeof r.recipeId === "string" && r.recipeId.length, `${tag}: recipeId required`);
  if (r.recipeId) { if (seenRecipeIds.has(r.recipeId)) errors.push(`${tag}: duplicate recipeId`); seenRecipeIds.add(r.recipeId); }
  req(typeof r.title === "string", `${tag}: title must be a string`);
  req(CATEGORIES.has(r.category), `${tag}: category must be breakfast|lunch|dinner (got '${r.category}')`);
  req(typeof r.image === "string" && r.image.length, `${tag}: image (local path) required`);
  if (typeof r.image === "string") resolveImg(r.image, tag + " image");
  req(Number.isInteger(r.serves), `${tag}: serves must be an int`);
  req(Number.isInteger(r.timeMin), `${tag}: timeMin must be an int`);
  req(typeof r.type === "string", `${tag}: type must be a string`);
  req(Array.isArray(r.ingredients) && r.ingredients.every((x) => typeof x === "string"), `${tag}: ingredients must be [string]`);
  req(Array.isArray(r.method) && r.method.every((x) => typeof x === "string"), `${tag}: method must be [string]`);
  req(r.nutrition && typeof r.nutrition === "object", `${tag}: nutrition map required`);
  if (r.nutrition) for (const k of ["kcal", "protein", "carbs", "fat", "fibre", "sugar"]) {
    req(typeof r.nutrition[k] === "number", `${tag}: nutrition.${k} must be a number`);
  }
  req(typeof r.note === "string", `${tag}: note must be a string`);
  req(Number.isInteger(r.order), `${tag}: order must be an int`);
  req(typeof r.published === "boolean", `${tag}: published must be a bool`);
});

if (errors.length) {
  console.error(`\n  ${errors.length} validation error(s):`);
  for (const e of errors) console.error("   - " + e);
  process.exit(1);
}
log(`Validated program '${program.programId}' — ${program.recipes.length} recipe(s). OK.`);

if (dryRun) { log("--dry-run: validation only, no uploads or writes. Done."); process.exit(0); }

// ---- init admin ------------------------------------------------------------------------------
if (!keyPath) die("no service-account key. Set GOOGLE_APPLICATION_CREDENTIALS or pass --key <key.json>.");
const keyAbs = path.resolve(keyPath.replace(/^~/, process.env.HOME || "~"));
if (!fs.existsSync(keyAbs)) die(`service-account key not found: ${keyAbs}`);
const creds = JSON.parse(fs.readFileSync(keyAbs, "utf8"));
if (creds.project_id !== PROJECT_ID) die(`key is for project '${creds.project_id}', expected '${PROJECT_ID}'. Refusing to run.`);

const app = initializeApp({ credential: cert(creds), storageBucket: BUCKET });
const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
log(`Admin SDK ready. project=${PROJECT_ID} bucket=${BUCKET}${usingEmulator ? "  [EMULATOR]" : "  [LIVE]"}`);

// token-free public download URL (object is made public below).
function publicUrl(objectPath) {
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media`;
}

async function uploadImage(localAbs, ext, objectPath, label) {
  const contentType = EXT_CONTENT_TYPE[ext];
  await bucket.upload(localAbs, {
    destination: objectPath,
    metadata: { contentType, cacheControl: "public, max-age=86400" },
  });
  // Public read, token-free (the app loads via plain ?alt=media). Emulator has no makePublic.
  if (!usingEmulator) { try { await bucket.file(objectPath).makePublic(); } catch (e) { console.warn(`  warn: makePublic failed for ${objectPath}: ${e.message}`); } }
  const url = publicUrl(objectPath);
  log(`  uploaded ${label}: ${objectPath}`);
  return url;
}

// ---- run -------------------------------------------------------------------------------------
(async () => {
  const pid = program.programId;

  const bannerObject = `content/programs/${pid}/banner${banner.ext}`;
  const bannerUrl = await uploadImage(banner.abs, banner.ext, bannerObject, "banner");

  const programRef = db.collection("mealPrograms").doc(pid);
  await programRef.set({
    name: program.name,
    blurb: program.blurb,
    bannerImageUrl: bannerUrl,
    order: program.order,
    published: program.published,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  log(`  wrote mealPrograms/${pid}`);

  let n = 0;
  for (const r of program.recipes) {
    const imgAbs = path.isAbsolute(r.image) ? r.image : path.resolve(baseDir, r.image);
    const ext = path.extname(imgAbs).toLowerCase();
    const obj = `content/programs/${pid}/recipes/${r.recipeId}${ext}`;
    const imageUrl = await uploadImage(imgAbs, ext, obj, `recipe ${r.recipeId}`);

    await programRef.collection("recipes").doc(r.recipeId).set({
      title: r.title,
      category: r.category,
      imageUrl,
      serves: r.serves,
      timeMin: r.timeMin,
      type: r.type,
      ingredients: r.ingredients,
      method: r.method,
      nutrition: {
        kcal: r.nutrition.kcal, protein: r.nutrition.protein, carbs: r.nutrition.carbs,
        fat: r.nutrition.fat, fibre: r.nutrition.fibre, sugar: r.nutrition.sugar,
      },
      note: r.note,
      order: r.order,
      published: r.published,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    log(`  wrote mealPrograms/${pid}/recipes/${r.recipeId}`);
    n++;
  }

  log(`\nDone. Program '${pid}' + ${n} recipe(s) upserted. Banner + ${n} recipe image(s) uploaded.`);
  process.exit(0);
})().catch((e) => { console.error("\n  UPLOAD FAILED:", e); process.exit(1); });
