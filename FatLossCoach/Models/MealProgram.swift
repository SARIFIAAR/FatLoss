import SwiftUI

// MARK: - Ariana meal program content model
//
// A curated, chef-authored meal program surfaced in the Nutrition tab. Distinct from the
// generic `Recipe` catalog (`Models/Nutrition.swift`): those are the plan-builder's swappable
// meal suggestions; this is a branded program with studio photography and full recipes.
//
// Types are namespaced under `MealProgram` to avoid colliding with the global `Recipe` type.
// The CEO's spec asked for `MealCategory`, `RecipeNutrition`, `Recipe`, `MealProgram` — the
// shapes and field names below mirror that spec; only the nested names differ to stay collision-free.
//
// Honest-numbers note (brand rule): every nutrition value here is transcribed verbatim from
// `docs/nutrition/ariana/ariana-breakfast-recipes.md`, which states the figures are per-serving
// ESTIMATES from USDA-class reference values (semi-skimmed milk assumed, "to taste" extras not
// counted), not lab measurements. `RecipeNutrition.isEstimate` carries that forward so any surface
// can label it. Logging a recipe writes those same numbers into a MealEntry — no silent re-derivation.

enum MealCategory: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Maps to the `MealEntry.slot` keys used by the diary/Store (Plan.meals keys).
    var slotKey: String { rawValue }
}

/// A curated meal program and its recipes.
///
/// Now REMOTE-driven: the canonical copy lives in Firestore (`mealPrograms/{id}` + a `recipes`
/// subcollection — see `ContentService`), so new programs/recipes can ship without an app build. The
/// types below are `Codable` so `ContentService` can both map them from Firestore and cache them to
/// disk, and `Identifiable` so the Program tab can `ForEach` over a fetched list. The hardcoded
/// `MealProgram.ariana` (below) is kept as the first-run / offline fallback until the cache or a live
/// fetch supersedes it.
///
/// Field-name note (shared schema, written down for the Android port): remote keys are
/// `name/blurb/bannerImageUrl/order/published/updatedAt` on the program and
/// `title/category/imageUrl/serves/timeMin/type/ingredients/method/nutrition{kcal,protein,carbs,fat,fibre,sugar}/note/order/published`
/// on each recipe. Image fields are plain public URLs (no auth token). All nutrition values are
/// per-serving ESTIMATES (brand honest-numbers rule); `Nutrition.isEstimate` carries that to the UI.
struct MealProgram: Identifiable, Codable, Hashable {
    struct Nutrition: Hashable, Codable {
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fibre: Double
        var sugar: Double
        /// All program figures are estimates (see the doc's honest note); kept explicit so UI can say so.
        var isEstimate: Bool = true

        private enum CodingKeys: String, CodingKey { case kcal, protein, carbs, fat, fibre, sugar, isEstimate }
        init(kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double, sugar: Double, isEstimate: Bool = true) {
            self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
            self.fibre = fibre; self.sugar = sugar; self.isEstimate = isEstimate
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kcal = (try? c.decode(Double.self, forKey: .kcal)) ?? 0
            protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
            carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
            fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
            fibre = (try? c.decode(Double.self, forKey: .fibre)) ?? 0
            sugar = (try? c.decode(Double.self, forKey: .sugar)) ?? 0
            isEstimate = (try? c.decode(Bool.self, forKey: .isEstimate)) ?? true
        }
    }

    struct Recipe: Identifiable, Hashable, Codable {
        var id: String
        var title: String
        var category: MealCategory
        var imageName: String          // Assets.xcassets imageset used as fallback (bundled studio photo)
        var imageURL: String?          // remote studio photo (plain public URL); nil for the bundled seed
        var serves: Int
        var timeMin: Int               // prep + cook, minutes
        var type: String               // e.g. "Hot porridge" / "Overnight oats"
        var ingredients: [String]
        var method: [String]
        var nutrition: Nutrition
        var note: String               // one-line "why it's good"

        init(id: String, title: String, category: MealCategory, imageName: String, imageURL: String? = nil,
             serves: Int, timeMin: Int, type: String, ingredients: [String], method: [String],
             nutrition: Nutrition, note: String) {
            self.id = id; self.title = title; self.category = category
            self.imageName = imageName; self.imageURL = imageURL
            self.serves = serves; self.timeMin = timeMin; self.type = type
            self.ingredients = ingredients; self.method = method; self.nutrition = nutrition; self.note = note
        }
    }

    var id: String
    var name: String
    var blurb: String
    var bannerImageURL: String?        // remote program banner (plain public URL); nil for the bundled seed
    var bannerImageName: String        // Assets.xcassets imageset used as fallback (bundled banner)
    var recipes: [Recipe]

    init(id: String, name: String, blurb: String, bannerImageURL: String? = nil,
         bannerImageName: String = "ariana-banner", recipes: [Recipe]) {
        self.id = id; self.name = name; self.blurb = blurb
        self.bannerImageURL = bannerImageURL; self.bannerImageName = bannerImageName; self.recipes = recipes
    }

    /// Recipes in a given category, in authored order.
    func recipes(in category: MealCategory) -> [Recipe] {
        recipes.filter { $0.category == category }
    }
}

// MARK: - The Ariana program (breakfasts)

extension MealProgram {
    /// Source of truth: `docs/nutrition/ariana/ariana-breakfast-recipes.md`. Lunch & Dinner are
    /// intentionally empty ("coming soon") until their content is authored and approved.
    static let ariana = MealProgram(
        id: "ariana",
        name: "The Ariana Program",
        blurb: "Plant-forward porridge & overnight-oat bowls — slow-release oats, real fruit, and a "
             + "handful of seeds or nuts. Build-your-own, whole-food breakfasts to feel good about. "
             + "Nutrition figures are per-serving estimates, a guide for your day — never a prescription.",
        bannerImageName: "ariana-banner",
        recipes: [
            Recipe(
                id: "ariana-b01",
                title: "Golden Turmeric Porridge",
                category: .breakfast,
                imageName: "ariana-b01",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice (or water)",
                    "1/2 ripe banana (~60 g), mashed into the porridge",
                    "1/4 tsp ground turmeric",
                    "Pinch of black pepper (helps the turmeric; optional)",
                    "60 g fresh blueberries",
                    "15 g pecans (about 4 halves)",
                    "10 g walnuts",
                    "Drizzle of honey or maple — to taste, optional",
                ],
                method: [
                    "Simmer oats and milk 5–6 min, stirring, until creamy.",
                    "Stir in the mashed banana, turmeric, and a pinch of black pepper.",
                    "Spoon into a bowl. Top with blueberries, pecans, and walnuts.",
                    "Finish with an optional drizzle of honey.",
                ],
                nutrition: Nutrition(kcal: 455, protein: 14, carbs: 55, fat: 20, fibre: 9, sugar: 20),
                note: "Oats and banana give steady, slow-release energy, while pecans and walnuts add "
                    + "wholesome plant fats — a warm, satisfying start to the day."
            ),
            Recipe(
                id: "ariana-b02",
                title: "Blood-Orange & Apple Bircher",
                category: .breakfast,
                imageName: "ariana-b02",
                serves: 1, timeMin: 10, type: "Overnight / Bircher",
                ingredients: [
                    "50 g rolled oats",
                    "150 ml milk of choice",
                    "60 g plain yoghurt (dairy or plant)",
                    "1 small apple (~100 g), grated",
                    "1/2 banana (~60 g), sliced",
                    "1/2 blood/red orange (~75 g), segmented",
                    "1 tbsp ground flax seeds (~10 g)",
                ],
                method: [
                    "The night before, mix oats, milk, yoghurt, and grated apple. Cover and chill overnight.",
                    "In the morning, loosen with a splash of milk if needed.",
                    "Top with banana slices, orange segments, and a sprinkle of flax.",
                ],
                nutrition: Nutrition(kcal: 420, protein: 15, carbs: 66, fat: 11, fibre: 11, sugar: 30),
                note: "Grated apple and flax bring plenty of fibre, and the Bircher soak makes the oats "
                    + "easy and gentle — a cool, refreshing bowl for warmer mornings."
            ),
            Recipe(
                id: "ariana-b03",
                title: "Banana-Apple Porridge with Chia & Sunflower",
                category: .breakfast,
                imageName: "ariana-b03",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "1/2 banana (~60 g), mashed in",
                    "1/2 apple (~75 g) grated into the porridge, plus a few slices to serve",
                    "1 tbsp chia seeds (~12 g)",
                    "1 tbsp sunflower seeds (~10 g)",
                    "60 g red grapes",
                ],
                method: [
                    "Cook oats and milk 5–6 min until creamy; stir in the mashed banana and grated apple.",
                    "Spoon into a bowl.",
                    "Top with a line of chia and sunflower seeds, apple slices, and grapes.",
                ],
                nutrition: Nutrition(kcal: 470, protein: 15, carbs: 66, fat: 16, fibre: 12, sugar: 28),
                note: "Chia and sunflower seeds add fibre and healthy fats, and the double hit of apple "
                    + "and grape keeps it naturally sweet without anything added."
            ),
            Recipe(
                id: "ariana-b04",
                title: "Flax & Chia Overnight Porridge with Summer Fruits",
                category: .breakfast,
                imageName: "ariana-b04",
                serves: 1, timeMin: 8, type: "Overnight oats",
                ingredients: [
                    "50 g rolled oats",
                    "220 ml milk of choice",
                    "1 tbsp chia seeds (~12 g)",
                    "1 tbsp ground flax seeds (~10 g)",
                    "1/2 banana (~60 g), mashed in (optional, for sweetness)",
                    "1 peach or nectarine (~120 g), diced",
                    "4 strawberries (~60 g), sliced",
                ],
                method: [
                    "The night before, stir oats, milk, chia, flax, and mashed banana together. Cover and chill.",
                    "In the morning, stir — it will be thick and pudding-like; loosen with milk if you like.",
                    "Top with diced peach and sliced strawberry.",
                ],
                nutrition: Nutrition(kcal: 440, protein: 16, carbs: 58, fat: 16, fibre: 14, sugar: 24),
                note: "The flax-and-chia combo makes this one of the highest-fibre bowls in the set, and "
                    + "the overnight soak means a two-minute, spoon-and-go morning."
            ),
            Recipe(
                id: "ariana-b05",
                title: "Build-Your-Own Porridge (Pistachio & Kiwi)",
                category: .breakfast,
                imageName: "ariana-b05",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "1/2 banana (~60 g), sliced or mashed",
                    "15 g pistachios (shelled)",
                    "10 g pecans",
                    "1 kiwi (~75 g), sliced",
                    "40 g blueberries",
                ],
                method: [
                    "Cook oats and milk 5–6 min until creamy; stir in banana.",
                    "Spoon into a bowl.",
                    "Top with pistachios, pecans, kiwi, and blueberries — arrange however you like.",
                ],
                nutrition: Nutrition(kcal: 460, protein: 15, carbs: 58, fat: 19, fibre: 9, sugar: 20),
                note: "This is the \"make it yours\" bowl — swap the fruit and nuts to whatever's fresh "
                    + "and you keep the same wholesome, balanced shape every time."
            ),
            Recipe(
                id: "ariana-b06",
                title: "Banana-Cinnamon Porridge with Fresh Berries",
                category: .breakfast,
                imageName: "ariana-b06",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "1 small banana (~90 g), half mashed in + half sliced on top",
                    "1/2 tsp ground cinnamon",
                    "40 g raspberries",
                    "50 g red grapes",
                    "10 g pecans",
                ],
                method: [
                    "Cook oats and milk 5–6 min; stir in mashed banana and most of the cinnamon.",
                    "Spoon into a bowl; lay banana slices, raspberries, grapes, and pecans on top.",
                    "Dust with the remaining cinnamon.",
                ],
                nutrition: Nutrition(kcal: 430, protein: 13, carbs: 68, fat: 13, fibre: 10, sugar: 30),
                note: "Warming cinnamon and sweet banana make this a comforting bowl, and the fresh "
                    + "berries add fibre and a bright, tart finish."
            ),
            Recipe(
                id: "ariana-b07",
                title: "Forest-Fruits Porridge with Almond Butter & Nuts",
                category: .breakfast,
                imageName: "ariana-b07",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "80 g mixed frozen forest fruits (blueberry, blackberry, raspberry, cherry), stirred in while cooking",
                    "1 tbsp almond butter (~16 g)",
                    "10 g walnuts",
                    "8 g almonds",
                    "8 g pecans",
                    "Pinch of cinnamon — optional",
                ],
                method: [
                    "Cook oats and milk 5–6 min, adding the forest fruits for the last 2 min so they soften and colour the porridge.",
                    "Spoon into a bowl; swirl the almond butter on top.",
                    "Scatter walnuts, almonds, and pecans; add a pinch of cinnamon.",
                ],
                nutrition: Nutrition(kcal: 515, protein: 17, carbs: 52, fat: 27, fibre: 11, sugar: 17),
                note: "Almond butter and a trio of nuts make this a hearty, higher-fat bowl that keeps "
                    + "you full — ideal before a busy or active morning."
            ),
            Recipe(
                id: "ariana-b08",
                title: "Rose & Berry Forest Porridge",
                category: .breakfast,
                imageName: "ariana-b08",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "80 g mixed forest fruits (blueberry, cherry, raspberry), stirred in",
                    "1/4 tsp rose water (to taste — start small)",
                    "1/2 banana (~60 g), mashed in",
                    "12 g walnuts",
                    "8 g pecans",
                ],
                method: [
                    "Cook oats and milk 5–6 min; add forest fruits for the last 2 min, then the mashed banana.",
                    "Stir in the rose water a few drops at a time, tasting as you go.",
                    "Spoon into a bowl and top with walnuts and pecans.",
                ],
                nutrition: Nutrition(kcal: 430, protein: 14, carbs: 56, fat: 17, fibre: 10, sugar: 20),
                note: "The rose water turns a simple berry bowl into something special with nothing added "
                    + "but fragrance — a little everyday luxury."
            ),
            Recipe(
                id: "ariana-b09",
                title: "Pan-Cooked Banana Porridge with Fresh Berries",
                category: .breakfast,
                imageName: "ariana-b09",
                serves: 1, timeMin: 12, type: "Hot porridge (one pan)",
                ingredients: [
                    "50 g rolled oats",
                    "220 ml milk of choice (or water)",
                    "1 ripe banana (~100 g), mashed",
                    "5 strawberries (~75 g), diced",
                    "50 g blueberries",
                    "Pinch of cinnamon — optional",
                ],
                method: [
                    "Cook oats, milk, and mashed banana together 6–7 min, stirring, until thick and creamy.",
                    "Off the heat, fold in most of the strawberries and blueberries.",
                    "Scatter the rest on top; add a pinch of cinnamon.",
                ],
                nutrition: Nutrition(kcal: 395, protein: 13, carbs: 72, fat: 7, fibre: 9, sugar: 30),
                note: "Ripe banana does the sweetening, so there's nothing added — a simple, lower-fat "
                    + "bowl that comes together in one pan."
            ),
            Recipe(
                id: "ariana-b10",
                title: "Banana & Coconut Porridge with Mixed Nuts",
                category: .breakfast,
                imageName: "ariana-b10",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "1/2 banana (~60 g) mashed in + a few slices on top",
                    "10 g desiccated coconut",
                    "Mixed nuts (~25 g total): pecan, walnut, hazelnut, almond, pistachio",
                ],
                method: [
                    "Cook oats and milk 5–6 min until creamy; stir in the mashed banana.",
                    "Spoon into a bowl.",
                    "Sprinkle desiccated coconut down one side; pile the mixed nuts and banana slices on the other.",
                ],
                nutrition: Nutrition(kcal: 500, protein: 15, carbs: 52, fat: 26, fibre: 9, sugar: 15),
                note: "A varied handful of nuts brings a range of wholesome fats and real crunch, while "
                    + "coconut adds gentle sweetness and texture."
            ),
            Recipe(
                id: "ariana-b11",
                title: "Blueberry-Apple Porridge with Cinnamon, Flax & Turmeric",
                category: .breakfast,
                imageName: "ariana-b11",
                serves: 1, timeMin: 11, type: "Hot porridge",
                ingredients: [
                    "50 g rolled oats",
                    "200 ml milk of choice",
                    "1/2 apple (~75 g), grated in",
                    "1/2 banana (~60 g), mashed in",
                    "1 tbsp ground flax seeds (~10 g)",
                    "1/2 tsp ground cinnamon",
                    "1/4 tsp ground turmeric",
                    "Pinch of black pepper (optional)",
                    "50 g blueberries",
                ],
                method: [
                    "Cook oats and milk 5–6 min; stir in grated apple and mashed banana.",
                    "Stir through the flax, cinnamon, turmeric, and a pinch of black pepper.",
                    "Spoon into a bowl and top with blueberries.",
                ],
                nutrition: Nutrition(kcal: 425, protein: 14, carbs: 62, fat: 13, fibre: 12, sugar: 24),
                note: "Ground flax and apple push the fibre up, and the cinnamon-turmeric spicing makes a "
                    + "cosy, fragrant bowl from simple pantry staples."
            ),
        ]
    )
}

// MARK: - Bridge to the diary meal-logging path

extension MealProgram.Recipe {
    /// Build a `MealEntry` for a given day from this recipe's transcribed nutrition. Macros come
    /// straight from `RecipeNutrition` (no re-derivation) and the slot is the recipe's category.
    func mealEntry(on day: String) -> MealEntry {
        MealEntry(
            date: day,
            name: title,
            kcal: nutrition.kcal,
            protein: nutrition.protein,
            carbs: nutrition.carbs,
            fat: nutrition.fat,
            fibre: nutrition.fibre,
            sugar: nutrition.sugar,
            notes: "The Ariana Program · estimated nutrition",
            slot: category.slotKey
        )
    }
}
