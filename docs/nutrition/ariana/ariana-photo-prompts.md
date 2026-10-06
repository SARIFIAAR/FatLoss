# The Ariana Program — Cinematic Studio Photo Prompts

AI image-generation prompts to reshoot the 11 breakfast bowls with a consistent, premium, food-magazine look. Works in Midjourney, Flux, DALL·E 3, Google "Nano Banana"/Gemini, Ideogram, etc. The real snaps are in `photos/ariana-NN.jpg` — use them as visual reference (image-to-image) where the tool supports it, so the AI version matches the actual recipe.

> **Consistency is everything.** Keep the SHARED STYLE block identical across all 11 so the set looks like one shoot — vary only the food line. Same bowl, same surface, same light.

---

## SHARED STYLE (append to every prompt)

> *…professional overhead (flat-lay) food photography, matte off‑white ceramic bowl centered on a dark honed‑slate surface, soft diffused daylight from the upper left, gentle natural shadows, shallow depth of field, rich true‑to‑life colors, fresh glossy textures with fine detail on the oats, seeds, nuts and fruit, subtle steam, editorial food‑magazine styling, cinematic color grade, immaculate clean minimal composition, high resolution, extremely appetizing.* **--ar 1:1 --style raw** *(Midjourney)* / *photorealistic, 85mm, f/2.8* *(for DALL·E / Flux / Gemini)*

**Negative / avoid:** text, watermark, logos, hands, cutlery clutter, plastic look, over‑saturation, messy spills, artificial neon colors.

---

## The 11 prompts (subject line + SHARED STYLE)

**01 · Golden Turmeric Porridge** — *A warm golden turmeric oat porridge, topped with a crescent of fresh blueberries, a cluster of pecan and walnut halves, and a soft dollop of mashed banana in the center.*

**02 · Blood-Orange Bircher** — *Creamy bircher overnight oats, pale and smooth, topped with grated apple, two blood‑orange wheels, a scatter of golden flax seeds and thin banana coins.*

**03 · Banana-Apple Seed Porridge** — *A soft banana‑apple oat porridge, generously sprinkled with chia and sunflower seeds in the center, fanned green apple slices and a few glossy red grapes to the side.*

**04 · Flax & Chia Overnight Oats** — *Thick flax‑and‑chia overnight oats, visible seeds suspended in creamy oats, crowned with diced yellow peach/nectarine and halved ripe strawberries.*

**05 · Build-Your-Own Bowl** — *Classic oat porridge topped with crushed bright‑green pistachios, pecan halves, thin kiwi slices and plump blueberries, a few banana coins peeking through.*

**06 · Banana-Cinnamon Berry Porridge** — *Creamy banana‑cinnamon porridge dusted with cinnamon, topped with fresh raspberries, dark red grapes around the rim and scattered pecans.*

**07 · Forest-Fruit & Almond Butter** — *Deep purple forest‑fruit oat porridge with a glossy swirl of almond butter melting on top, surrounded by walnut, almond and pecan pieces.*

**08 · Rose Berry Porridge** — *A romantic deep‑pink rose‑scented berry porridge, rich magenta oats speckled with berries, topped with walnut and pecan halves, delicate and elegant.*

**09 · Banana-Mashed Rustic Porridge** — *Rustic banana‑mashed oat porridge with a homemade texture, studded and topped with fresh chopped strawberries and whole blueberries, warm and comforting.*

**10 · Banana-Coconut Nut Bowl** — *Smooth banana oat porridge with a neat line of desiccated coconut along one side and a generous cluster of mixed nuts (pecan, walnut, hazelnut, almond, pistachio) along the other, banana coins in the center.*

**11 · Blueberry-Apple Spiced Porridge** — *Creamy blueberry‑apple oat porridge topped with a crescent of blueberries and a warm dusting of cinnamon, ground flax and golden turmeric down the center.*

---

## How to run them
- **Best match to the real recipe:** use image‑to‑image with the matching `photos/ariana-NN.jpg` as a reference image + the prompt above (Midjourney `/imagine` with image URL, Flux/Gemini "edit with reference", DALL·E "use as reference").
- **From scratch:** just paste `SHARED STYLE + subject line`.
- Generate 4 variants each, pick the best, keep the same seed/style for cohesion.
- Export 1200×1200 (or larger) to match the cleaned set; drop finals next to the originals as `ariana-NN-studio.jpg`.

*Note: AI‑generated images are stylized interpretations — they won't be the exact bowl Ariana made. For a recipe/nutrition program that's usually fine (most apps use styled imagery), but if authenticity matters for a given dish, keep the real cleaned photo.*
