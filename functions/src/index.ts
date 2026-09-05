import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

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
export type MealAnalysis = z.infer<typeof MealAnalysis>;

const SYSTEM = `You are a registered dietitian estimating nutrition from a single meal photo for a fat-loss client (male, 49, 189 cm, ~105 kg, target 1,850 kcal/day).
Identify each distinct food or drink, estimate the portion from visual cues (plate size, utensils, hand, packaging), and estimate calories and macros using standard nutrition databases (USDA). Account for likely cooking oils, dressings and sauces. When unsure, choose the more common preparation and say so in notes. Totals must equal the sum of the items. If the image does not show food or drink, set is_food to false and return empty items with zero totals.`;

const ALLOWED_MEDIA = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

export const analyzeMeal = onCall(
  { region: "europe-west1", secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 120, memory: "512MiB", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to analyze meals.");
    }
    const data = request.data as { image?: string; mediaType?: string; hint?: string };
    const image = data?.image;
    const mediaType = (data?.mediaType ?? "image/jpeg") as "image/jpeg" | "image/png" | "image/webp" | "image/gif";
    if (!image || typeof image !== "string" || image.length < 100) {
      throw new HttpsError("invalid-argument", "Send a base64 JPEG in `image`.");
    }
    if (image.length > 7_000_000) {
      throw new HttpsError("invalid-argument", "Image too large — resize to ~1024 px before sending.");
    }
    if (!ALLOWED_MEDIA.has(mediaType)) {
      throw new HttpsError("invalid-argument", `Unsupported mediaType ${mediaType}.`);
    }

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
    const hint = data?.hint?.trim();

    let response: Anthropic.Beta.Messages.BetaMessage;
    try {
      response = await client.beta.messages.create({
        model: "claude-opus-5",
        max_tokens: 4000,
        system: SYSTEM,
        // Safety-classifier refusals are re-run on a fallback model inside the same call.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { format: zodOutputFormat(MealAnalysis), effort: "medium" },
        messages: [
          {
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
              {
                type: "text",
                text: hint
                  ? `Estimate the nutrition of this meal. Extra context from the user: ${hint}`
                  : "Estimate the nutrition of this meal.",
              },
            ],
          },
        ],
      });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) throw new HttpsError("resource-exhausted", "Busy, try again in a moment.");
      if (err instanceof Anthropic.APIConnectionError) throw new HttpsError("unavailable", "Could not reach the model.");
      if (err instanceof Anthropic.APIError) throw new HttpsError("internal", `Model error ${err.status ?? ""}.`);
      throw new HttpsError("internal", "Analysis failed.");
    }

    if (response.stop_reason === "refusal") {
      throw new HttpsError("failed-precondition", "The model declined to analyze this image.");
    }
    const text = response.content.find((b) => b.type === "text")?.text ?? "";
    const parsed = MealAnalysis.safeParse(JSON.parse(text));
    if (!parsed.success) {
      throw new HttpsError("internal", "Malformed analysis.");
    }
    return {
      ...parsed.data,
      model: response.model,
      usage: { input: response.usage.input_tokens, output: response.usage.output_tokens },
    };
  },
);
