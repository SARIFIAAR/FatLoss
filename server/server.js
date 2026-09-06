// Fat Loss Coach — meal photo analyzer.
// POST /analyze  { image: <base64 jpeg>, mediaType?, hint? }  with  Authorization: Bearer <Firebase ID token>
// Verifies the Firebase token against Google's public keys (no service account needed), then asks Claude
// for a structured nutrition estimate. Runs on Fly.io; the Anthropic key never reaches the phone.
import http from "node:http";
import { createRemoteJWKSet, jwtVerify } from "jose";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";

const PORT = Number(process.env.PORT ?? 8080);
const PROJECT = process.env.FIREBASE_PROJECT_ID ?? "fat-loss-6516d";
const MODEL = process.env.MODEL ?? "claude-opus-5";          // e.g. fly secrets set MODEL=claude-sonnet-5
const MAX_BODY = 10 * 1024 * 1024;

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set");
  process.exit(1);
}
const client = new Anthropic();
const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

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

const SYSTEM = `You are a registered dietitian estimating nutrition from a single meal photo for a fat-loss client (male, 49, 189 cm, ~105 kg, target 1,850 kcal/day).
Identify each distinct food or drink, estimate the portion from visual cues (plate size, utensils, hand, packaging), and estimate calories and macros using standard nutrition databases (USDA). Account for likely cooking oils, dressings and sauces. When unsure, choose the more common preparation and say so in notes. Totals must equal the sum of the items. If the image does not show food or drink, set is_food to false and return empty items with zero totals.`;

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
    return payload.sub;
  } catch {
    throw new HttpError(401, "Your session expired. Sign in again.");
  }
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
  if (!image || typeof image !== "string" || image.length < 100) throw new HttpError(400, "Send a base64 JPEG in `image`.");
  if (!ALLOWED_MEDIA.has(mediaType)) throw new HttpError(400, `Unsupported mediaType ${mediaType}.`);

  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 4000,
      system: SYSTEM,
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

function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
  res.end(body);
}

http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true, model: MODEL });
    if (req.method === "POST" && req.url === "/analyze") {
      const uid = await verifyUser(req);
      const body = await readJSON(req);
      const started = Date.now();
      const result = await analyze(body);
      console.log(JSON.stringify({ uid, ms: Date.now() - started, kcal: result.total_kcal, model: result.model, usage: result.usage }));
      return send(res, 200, result);
    }
    return send(res, 404, { error: "Not found" });
  } catch (err) {
    const status = err instanceof HttpError ? err.status : 500;
    if (status >= 500) console.error(err);
    return send(res, status, { error: err.message ?? "Analysis failed." });
  }
}).listen(PORT, "0.0.0.0", () => console.log(`analyzer listening on ${PORT} (model ${MODEL})`));
