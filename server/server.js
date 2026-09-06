// Fat Loss Coach — meal photo analyzer + admin dashboard.
//   POST /analyze        { image: <base64 jpeg>, mediaType?, hint?, context? }  Authorization: Bearer <Firebase ID token>
//   GET  /health
//   GET  /admin          coach dashboard (needs ADMIN_KEY); /admin/api/* JSON behind header x-admin-key
// Verifies the Firebase token against Google's public keys (no service account needed for that), then asks
// Claude for a structured nutrition estimate. With FIREBASE_SERVICE_ACCOUNT set, every scan is also logged
// to Firestore `scans/` and the dashboard can read each user's per-day rows written by the app.
import http from "node:http";
import { readFileSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import * as db from "./firestore.js";

const PORT = Number(process.env.PORT ?? 8080);
const PROJECT = process.env.FIREBASE_PROJECT_ID ?? "fat-loss-6516d";
const MODEL = process.env.MODEL ?? "claude-opus-5";          // e.g. fly secrets set MODEL=claude-sonnet-5
const ADMIN_KEY = process.env.ADMIN_KEY ?? "";               // fly secrets set ADMIN_KEY=<long random string>
const MAX_BODY = 10 * 1024 * 1024;

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set");
  process.exit(1);
}
if (!db.enabled) console.warn("FIREBASE_SERVICE_ACCOUNT not set: scans are not logged and /admin has no data");
if (!ADMIN_KEY) console.warn("ADMIN_KEY not set: /admin is disabled");

const client = new Anthropic();
const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);
const ADMIN_HTML = readFileSync(new URL("./admin.html", import.meta.url));

const FoodItem = z.object({
  name: z.string().describe("Short food name, e.g. 'Grilled chicken breast'"),
  portion: z.string().describe("Estimated portion in plain words, e.g. '150 g' or '1 cup'"),
  grams: z.number().describe("Estimated weight in grams"),
  kcal: z.number(),
  protein_g: z.number(),
  carbs_g: z.number(),
  fat_g: z.number(),
});
const MealAnalysis = z.object({
  is_food: z.boolean().describe("false if the photo does not show food or drink"),
  meal_name: z.string().describe("A 2-5 word name for the whole meal"),
  items: z.array(FoodItem),
  total_kcal: z.number(),
  total_protein_g: z.number(),
  total_carbs_g: z.number(),
  total_fat_g: z.number(),
  confidence: z.enum(["low", "medium", "high"]),
  notes: z.string().describe("One sentence: assumptions made (hidden oils, sauces, portion uncertainty). Empty if none."),
});

function systemPrompt(ctx) {
  const who = [];
  if (ctx?.currentWeightKg) who.push(`currently ~${Math.round(ctx.currentWeightKg)} kg`);
  if (ctx?.goalWeightKg) who.push(`goal ${Math.round(ctx.goalWeightKg)} kg`);
  if (ctx?.kcalTarget) who.push(`target ${ctx.kcalTarget} kcal/day`);
  if (ctx?.proteinTarget) who.push(`${ctx.proteinTarget} g protein/day`);
  const profile = who.length ? ` (${who.join(", ")})` : "";
  return `You are a registered dietitian estimating nutrition from a single meal photo for a fat-loss client${profile}.
Identify each distinct food or drink, estimate the portion from visual cues (plate size, utensils, hand, packaging), and estimate calories and macros using standard nutrition databases (USDA). Account for likely cooking oils, dressings and sauces. When unsure, choose the more common preparation and say so in notes. Totals must equal the sum of the items. If the image does not show food or drink, set is_food to false and return empty items with zero totals.`;
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

async function analyze(body) {
  const image = body?.image;
  const mediaType = body?.mediaType ?? "image/jpeg";
  const hint = typeof body?.hint === "string" ? body.hint.trim() : "";
  const ctx = body?.context && typeof body.context === "object" ? body.context : null;
  if (!image || typeof image !== "string" || image.length < 100) throw new HttpError(400, "Send a base64 JPEG in `image`.");
  if (!ALLOWED_MEDIA.has(mediaType)) throw new HttpError(400, `Unsupported mediaType ${mediaType}.`);

  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 4000,
      system: systemPrompt(ctx),
      // Safety-classifier refusals are re-run on a fallback model inside the same call.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { format: zodOutputFormat(MealAnalysis), effort: "medium" },
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: hint ? `Estimate the nutrition of this meal. Extra context from the user: ${hint}` : "Estimate the nutrition of this meal." },
        ],
      }],
    });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) throw new HttpError(429, "Busy, try again in a moment.");
    if (err instanceof Anthropic.APIConnectionError) throw new HttpError(503, "Could not reach the model.");
    if (err instanceof Anthropic.APIError) { console.error("anthropic", err.status, err.message); throw new HttpError(502, `Model error ${err.status ?? ""}.`); }
    throw err;
  }
  if (response.stop_reason === "refusal") throw new HttpError(422, "The model declined to analyze this image.");
  const text = response.content.find((b) => b.type === "text")?.text ?? "";
  const parsed = MealAnalysis.safeParse(JSON.parse(text));
  if (!parsed.success) throw new HttpError(502, "Malformed analysis.");
  return {
    ...parsed.data,
    model: response.model,
    usage: { input: response.usage.input_tokens, output: response.usage.output_tokens },
  };
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

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  try {
    if (req.method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true, model: MODEL, firestore: db.enabled, admin: Boolean(ADMIN_KEY) });

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
    return send(res, 404, { error: "Not found" });
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    if (status >= 500) console.error(err);
    return send(res, status, { error: err.message ?? "Analysis failed." });
  }
}).listen(PORT, "0.0.0.0", () => console.log(`analyzer listening on ${PORT} (model ${MODEL}, firestore ${db.enabled ? "on" : "off"}, admin ${ADMIN_KEY ? "on" : "off"})`));
