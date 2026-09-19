import SwiftUI

// MARK: - Diet programs (Lifesum-style "Program" section)

struct DietProgram: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let icon: String
    let colorHex: UInt32
    let about: String
    let carbPct: Int
    let proteinPct: Int
    let fatPct: Int
    let eat: [String]
    let avoid: [String]
    let sampleDay: [String]
    var fasting: FastingSchedule? = nil     // set for fasting plans (5:2, 16:8)

    var color: Color { Color(hex: colorHex) }

    /// Macro grams for a given daily calorie goal, from this plan's split.
    func macros(forKcal kcal: Int) -> (protein: Int, carbs: Int, fat: Int) {
        let p = Double(kcal) * Double(proteinPct) / 100 / 4
        let c = Double(kcal) * Double(carbPct) / 100 / 4
        let f = Double(kcal) * Double(fatPct) / 100 / 9
        return (Int(p.rounded()), Int(c.rounded()), Int(f.rounded()))
    }
}

/// A fasting protocol. `eatingWindowHours` drives the daily timer; `label` is the human name.
struct FastingSchedule: Hashable {
    let label: String            // "16:8" · "5:2"
    let eatingWindowHours: Int   // hours you may eat (16:8 = 8); 0 for day-based (5:2)
    let blurb: String
}

enum ProgramCatalog {
    static let all: [DietProgram] = [
        DietProgram(id: "balanced", name: "Balanced", tagline: "Sustainable everyday eating",
            icon: "circle.grid.2x2.fill", colorHex: 0x43CB00,
            about: "A flexible, well-rounded split that's easy to stick to. Great default for steady fat loss without cutting any food group.",
            carbPct: 40, proteinPct: 30, fatPct: 30,
            eat: ["Lean protein", "Whole grains", "Vegetables & fruit", "Healthy fats"],
            avoid: ["Ultra-processed snacks", "Sugary drinks"],
            sampleDay: ["Oats with berries & yoghurt", "Chicken & quinoa bowl", "Salmon, potatoes & greens"]),
        DietProgram(id: "high_protein", name: "High Protein", tagline: "Protect muscle while cutting",
            icon: "bolt.fill", colorHex: 0x42B883,
            about: "Prioritises protein to preserve lean mass and keep you full in a deficit. Ideal alongside strength training.",
            carbPct: 35, proteinPct: 40, fatPct: 25,
            eat: ["Chicken, turkey, fish", "Eggs & dairy", "Legumes", "Protein shakes"],
            avoid: ["Low-protein fast food", "Excess refined carbs"],
            sampleDay: ["Egg-white omelette & oats", "Grilled chicken salad", "Steak, beans & veg"]),
        DietProgram(id: "keto", name: "Keto", tagline: "Very low carb, high fat",
            icon: "flame.fill", colorHex: 0xF0A030,
            about: "Cuts carbs hard to shift the body toward burning fat for fuel. Requires consistency; not for everyone.",
            carbPct: 5, proteinPct: 25, fatPct: 70,
            eat: ["Avocado & olive oil", "Eggs, meat, fish", "Nuts & seeds", "Leafy greens"],
            avoid: ["Bread, pasta, rice", "Sugar & most fruit", "Starchy veg"],
            sampleDay: ["Avocado & eggs", "Salmon with greens", "Steak & buttered broccoli"]),
        DietProgram(id: "low_carb", name: "Low Carb", tagline: "Fewer carbs, more control",
            icon: "leaf.fill", colorHex: 0x4CA9E8,
            about: "A gentler carb reduction than keto — steady energy and appetite control without full restriction.",
            carbPct: 20, proteinPct: 35, fatPct: 45,
            eat: ["Protein at every meal", "Non-starchy veg", "Healthy fats", "Berries"],
            avoid: ["Sugary foods", "Large portions of grains"],
            sampleDay: ["Greek yoghurt & nuts", "Chicken & big salad", "Fish, courgette & olive oil"]),
        DietProgram(id: "mediterranean", name: "Mediterranean", tagline: "Heart-healthy & flexible",
            icon: "sun.max.fill", colorHex: 0x0093E7,
            about: "Built around vegetables, olive oil, fish and whole grains. One of the most evidence-backed ways to eat.",
            carbPct: 45, proteinPct: 25, fatPct: 30,
            eat: ["Olive oil", "Fish & seafood", "Vegetables & legumes", "Whole grains"],
            avoid: ["Red & processed meat", "Refined sugar"],
            sampleDay: ["Yoghurt, honey & walnuts", "Tuna & bean salad", "Grilled fish, veg & farro"]),
        DietProgram(id: "clean_eating", name: "Clean Eating", tagline: "Whole foods, minimally processed",
            icon: "sparkles", colorHex: 0xA96CF0,
            about: "Focuses on real, minimally processed food. No macro extremes — just quality ingredients.",
            carbPct: 40, proteinPct: 30, fatPct: 30,
            eat: ["Fresh produce", "Whole grains", "Unprocessed protein", "Nuts & seeds"],
            avoid: ["Packaged snacks", "Added sugar", "Refined oils"],
            sampleDay: ["Overnight oats & fruit", "Buddha bowl", "Baked chicken & roast veg"]),
        DietProgram(id: "paleo", name: "Paleo", tagline: "Eat like our ancestors",
            icon: "tortoise.fill", colorHex: 0xF0C930,
            about: "Whole foods only — meat, fish, veg, fruit, nuts. No grains, dairy or processed food.",
            carbPct: 25, proteinPct: 35, fatPct: 40,
            eat: ["Meat & fish", "Eggs", "Vegetables & fruit", "Nuts & seeds"],
            avoid: ["Grains & legumes", "Dairy", "Processed food"],
            sampleDay: ["Eggs & avocado", "Chicken & veg stir-fry", "Beef & sweet potato"]),
        DietProgram(id: "plant_based", name: "Plant-based", tagline: "Mostly plants, lots of fibre",
            icon: "leaf.circle.fill", colorHex: 0x43CB00,
            about: "Centres beans, grains, veg and fruit. High fibre and satiating; mind protein and B12.",
            carbPct: 50, proteinPct: 25, fatPct: 25,
            eat: ["Beans & lentils", "Tofu & tempeh", "Whole grains", "Vegetables & fruit"],
            avoid: ["Meat & fish", "Most dairy"],
            sampleDay: ["Tofu scramble", "Lentil & grain bowl", "Chickpea curry & rice"]),
        DietProgram(id: "fasting_168", name: "16:8 Fasting", tagline: "Eat in an 8-hour window",
            icon: "clock.fill", colorHex: 0x4C6CF0,
            about: "Fast for 16 hours, eat within an 8-hour window each day. Simple time-restricted eating that pairs with any diet.",
            carbPct: 40, proteinPct: 30, fatPct: 30,
            eat: ["Balanced meals in-window", "Plenty of water", "Black coffee / tea while fasting"],
            avoid: ["Calories outside the window", "Sugary drinks"],
            sampleDay: ["12:00 — first meal", "15:30 — lunch/snack", "19:30 — dinner (window closes 20:00)"],
            fasting: FastingSchedule(label: "16:8", eatingWindowHours: 8, blurb: "16h fast · 8h eating window")),
        DietProgram(id: "fasting_52", name: "5:2 Fasting", tagline: "Two low-calorie days a week",
            icon: "calendar", colorHex: 0x4C6CF0,
            about: "Eat normally 5 days a week; on 2 non-consecutive days keep to ~500–600 kcal. Weekly calorie reduction without daily restriction.",
            carbPct: 40, proteinPct: 35, fatPct: 25,
            eat: ["Normal balanced days ×5", "High-protein, high-volume on fast days"],
            avoid: ["Back-to-back fast days", "Refined carbs on fast days"],
            sampleDay: ["Normal day: 3 balanced meals", "Fast day: ~500 kcal, protein-focused", "Stay hydrated"],
            fasting: FastingSchedule(label: "5:2", eatingWindowHours: 0, blurb: "5 normal days · 2 low-calorie days")),
    ]

    static func by(id: String?) -> DietProgram? { all.first { $0.id == id } }
}

// MARK: - Common foods (instant quick-add DB)

/// A curated everyday food with a sensible default serving — for one-tap logging without a search.
struct CommonFood: Identifiable, Hashable {
    let id: String
    let name: String
    let serving: String        // e.g. "1 egg", "100 g", "1 cup"
    let icon: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum CommonFoods {
    static let all: [CommonFood] = [
        CommonFood(id: "egg", name: "Egg", serving: "1 large", icon: "circle.fill", kcal: 78, protein: 6, carbs: 0.6, fat: 5),
        CommonFood(id: "banana", name: "Banana", serving: "1 medium", icon: "leaf.fill", kcal: 105, protein: 1.3, carbs: 27, fat: 0.4),
        CommonFood(id: "apple", name: "Apple", serving: "1 medium", icon: "leaf.fill", kcal: 95, protein: 0.5, carbs: 25, fat: 0.3),
        CommonFood(id: "chicken", name: "Chicken breast", serving: "100 g", icon: "fork.knife", kcal: 165, protein: 31, carbs: 0, fat: 3.6),
        CommonFood(id: "rice", name: "Cooked rice", serving: "1 cup", icon: "bowl.fill", kcal: 205, protein: 4.3, carbs: 45, fat: 0.4),
        CommonFood(id: "oats", name: "Oats (dry)", serving: "50 g", icon: "bowl.fill", kcal: 190, protein: 6.5, carbs: 33, fat: 3.5),
        CommonFood(id: "gyoghurt", name: "Greek yoghurt", serving: "150 g", icon: "circle.fill", kcal: 130, protein: 15, carbs: 6, fat: 5),
        CommonFood(id: "milk", name: "Milk", serving: "1 cup", icon: "drop.fill", kcal: 122, protein: 8, carbs: 12, fat: 5),
        CommonFood(id: "bread", name: "Bread", serving: "1 slice", icon: "square.fill", kcal: 80, protein: 3, carbs: 15, fat: 1),
        CommonFood(id: "avocado", name: "Avocado", serving: "1/2", icon: "leaf.fill", kcal: 160, protein: 2, carbs: 9, fat: 15),
        CommonFood(id: "salmon", name: "Salmon", serving: "100 g", icon: "fish.fill", kcal: 208, protein: 20, carbs: 0, fat: 13),
        CommonFood(id: "peanutbutter", name: "Peanut butter", serving: "1 tbsp", icon: "circle.fill", kcal: 94, protein: 4, carbs: 3, fat: 8),
        CommonFood(id: "coffee", name: "Coffee (black)", serving: "1 cup", icon: "cup.and.saucer.fill", kcal: 2, protein: 0.3, carbs: 0, fat: 0),
        CommonFood(id: "protein", name: "Protein shake", serving: "1 scoop", icon: "bolt.fill", kcal: 120, protein: 24, carbs: 3, fat: 1.5),
        CommonFood(id: "almonds", name: "Almonds", serving: "28 g", icon: "circle.fill", kcal: 164, protein: 6, carbs: 6, fat: 14),
        CommonFood(id: "potato", name: "Potato", serving: "1 medium", icon: "circle.fill", kcal: 163, protein: 4.3, carbs: 37, fat: 0.2),
    ]
}

// MARK: - Recipes

struct Recipe: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String        // Breakfast / Lunch / Dinner / Snack
    let icon: String
    let colorHex: UInt32
    let kcal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let minutes: Int
    let tags: [String]          // program ids it suits
    let ingredients: [String]
    let steps: [String]

    var color: Color { Color(hex: colorHex) }
}

enum RecipeCatalog {
    static let categories = ["Breakfast", "Lunch", "Dinner", "Snack"]

    static let all: [Recipe] = [
        Recipe(id: "r1", name: "Berry Protein Oats", category: "Breakfast", icon: "bowl.fill", colorHex: 0x42B883,
            kcal: 380, protein: 30, carbs: 45, fat: 9, minutes: 5, tags: ["balanced", "high_protein", "clean_eating"],
            ingredients: ["50g rolled oats", "1 scoop whey", "150g Greek yoghurt", "80g mixed berries", "Cinnamon"],
            steps: ["Cook oats with water.", "Stir in whey off the heat.", "Top with yoghurt, berries and cinnamon."]),
        Recipe(id: "r2", name: "Avocado & Eggs", category: "Breakfast", icon: "fork.knife", colorHex: 0xF0A030,
            kcal: 420, protein: 20, carbs: 8, fat: 34, minutes: 10, tags: ["keto", "low_carb", "paleo"],
            ingredients: ["2 eggs", "1/2 avocado", "Olive oil", "Chilli flakes", "Salt & pepper"],
            steps: ["Fry or poach the eggs.", "Slice avocado onto a plate.", "Add eggs, drizzle oil, season."]),
        Recipe(id: "r3", name: "Tofu Scramble", category: "Breakfast", icon: "leaf.fill", colorHex: 0x43CB00,
            kcal: 300, protein: 22, carbs: 12, fat: 18, minutes: 12, tags: ["plant_based", "clean_eating"],
            ingredients: ["200g firm tofu", "Turmeric", "Spinach", "Cherry tomatoes", "Olive oil"],
            steps: ["Crumble tofu into a hot pan with oil.", "Add turmeric and veg.", "Cook 5–7 min, season."]),
        Recipe(id: "r4", name: "Grilled Chicken Salad", category: "Lunch", icon: "leaf.circle.fill", colorHex: 0x42B883,
            kcal: 450, protein: 45, carbs: 20, fat: 20, minutes: 20, tags: ["high_protein", "low_carb", "balanced"],
            ingredients: ["180g chicken breast", "Mixed leaves", "Cherry tomatoes", "Cucumber", "Olive oil & lemon"],
            steps: ["Grill seasoned chicken.", "Toss salad with oil and lemon.", "Slice chicken over the top."]),
        Recipe(id: "r5", name: "Tuna & Bean Salad", category: "Lunch", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 400, protein: 38, carbs: 30, fat: 12, minutes: 8, tags: ["mediterranean", "high_protein"],
            ingredients: ["1 tin tuna", "1/2 tin cannellini beans", "Red onion", "Parsley", "Olive oil & lemon"],
            steps: ["Drain tuna and beans.", "Combine with onion and parsley.", "Dress with oil and lemon."]),
        Recipe(id: "r6", name: "Buddha Bowl", category: "Lunch", icon: "circle.grid.2x2.fill", colorHex: 0xA96CF0,
            kcal: 520, protein: 22, carbs: 65, fat: 18, minutes: 25, tags: ["plant_based", "clean_eating", "balanced"],
            ingredients: ["100g quinoa", "1/2 tin chickpeas", "Roast veg", "Avocado", "Tahini dressing"],
            steps: ["Cook quinoa.", "Roast the veg and chickpeas.", "Assemble bowl, add avocado and tahini."]),
        Recipe(id: "r7", name: "Salmon & Greens", category: "Dinner", icon: "fish.fill", colorHex: 0xF0A030,
            kcal: 480, protein: 40, carbs: 10, fat: 30, minutes: 20, tags: ["keto", "low_carb", "mediterranean"],
            ingredients: ["180g salmon fillet", "Broccoli", "Asparagus", "Butter or olive oil", "Lemon"],
            steps: ["Pan-sear salmon skin-side down.", "Steam the greens.", "Finish with butter and lemon."]),
        Recipe(id: "r8", name: "Steak & Sweet Potato", category: "Dinner", icon: "flame.fill", colorHex: 0xF0C930,
            kcal: 620, protein: 48, carbs: 40, fat: 28, minutes: 30, tags: ["paleo", "high_protein"],
            ingredients: ["200g steak", "1 sweet potato", "Green beans", "Olive oil", "Garlic"],
            steps: ["Roast sweet potato wedges.", "Sear steak to your liking, rest.", "Steam beans, plate up."]),
        Recipe(id: "r9", name: "Chickpea Curry", category: "Dinner", icon: "leaf.fill", colorHex: 0x43CB00,
            kcal: 540, protein: 20, carbs: 70, fat: 18, minutes: 30, tags: ["plant_based"],
            ingredients: ["2 tins chickpeas", "Coconut milk (light)", "Curry paste", "Spinach", "Basmati rice"],
            steps: ["Fry curry paste.", "Add chickpeas and coconut milk, simmer.", "Stir in spinach, serve with rice."]),
        Recipe(id: "r10", name: "Greek Yoghurt & Nuts", category: "Snack", icon: "circle.fill", colorHex: 0x42B883,
            kcal: 220, protein: 18, carbs: 12, fat: 11, minutes: 2, tags: ["low_carb", "high_protein", "balanced"],
            ingredients: ["150g Greek yoghurt", "20g mixed nuts", "Drizzle of honey"],
            steps: ["Spoon yoghurt into a bowl.", "Top with nuts and honey."]),
        Recipe(id: "r11", name: "Protein Energy Balls", category: "Snack", icon: "circle.hexagongrid.fill", colorHex: 0xA96CF0,
            kcal: 180, protein: 10, carbs: 18, fat: 8, minutes: 10, tags: ["clean_eating", "high_protein"],
            ingredients: ["Oats", "Peanut butter", "1 scoop whey", "Honey", "Dark choc chips"],
            steps: ["Mix everything into a dough.", "Roll into balls.", "Chill 30 min."]),
        Recipe(id: "r12", name: "Veg & Hummus", category: "Snack", icon: "leaf.circle.fill", colorHex: 0x43CB00,
            kcal: 160, protein: 6, carbs: 18, fat: 8, minutes: 3, tags: ["plant_based", "clean_eating", "mediterranean"],
            ingredients: ["Carrot & pepper sticks", "Cucumber", "3 tbsp hummus"],
            steps: ["Slice the veg.", "Serve with hummus to dip."]),
        Recipe(id: "r13", name: "Protein Pancakes", category: "Breakfast", icon: "bowl.fill", colorHex: 0x42B883,
            kcal: 340, protein: 32, carbs: 30, fat: 10, minutes: 12, tags: ["high_protein", "balanced"],
            ingredients: ["1 banana", "2 eggs", "1 scoop whey", "40g oats", "Cinnamon"],
            steps: ["Blend everything to a batter.", "Cook small pancakes in a non-stick pan.", "Top with berries."]),
        Recipe(id: "r14", name: "Smoked Salmon Bagel", category: "Breakfast", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 400, protein: 26, carbs: 42, fat: 14, minutes: 6, tags: ["mediterranean", "balanced"],
            ingredients: ["1 wholegrain bagel", "80g smoked salmon", "Light cream cheese", "Capers & dill"],
            steps: ["Toast the bagel.", "Spread cream cheese.", "Top with salmon, capers and dill."]),
        Recipe(id: "r15", name: "Chia Pudding", category: "Breakfast", icon: "circle.fill", colorHex: 0xA96CF0,
            kcal: 280, protein: 12, carbs: 30, fat: 12, minutes: 5, tags: ["plant_based", "clean_eating"],
            ingredients: ["3 tbsp chia seeds", "200ml almond milk", "Berries", "Maple syrup"],
            steps: ["Mix chia and milk, chill overnight.", "Top with berries and a little maple."]),
        Recipe(id: "r16", name: "Turkey Wrap", category: "Lunch", icon: "fork.knife", colorHex: 0x42B883,
            kcal: 430, protein: 38, carbs: 38, fat: 14, minutes: 8, tags: ["high_protein", "balanced"],
            ingredients: ["Wholewheat wrap", "120g turkey breast", "Salad", "Light mayo/mustard"],
            steps: ["Lay out the wrap.", "Add turkey and salad.", "Roll tightly and slice."]),
        Recipe(id: "r17", name: "Lentil Soup", category: "Lunch", icon: "leaf.fill", colorHex: 0xF0A030,
            kcal: 360, protein: 20, carbs: 50, fat: 8, minutes: 30, tags: ["plant_based", "mediterranean", "clean_eating"],
            ingredients: ["200g red lentils", "Carrot, onion, celery", "Veg stock", "Cumin & lemon"],
            steps: ["Sauté the veg.", "Add lentils and stock, simmer 20 min.", "Season with cumin and lemon."]),
        Recipe(id: "r18", name: "Poke Bowl", category: "Lunch", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 500, protein: 35, carbs: 55, fat: 14, minutes: 15, tags: ["balanced", "high_protein"],
            ingredients: ["150g tuna or salmon", "Rice", "Edamame", "Avocado", "Soy & sesame"],
            steps: ["Cube the fish.", "Build the bowl over rice.", "Add toppings and dressing."]),
        Recipe(id: "r19", name: "Chicken Stir-fry", category: "Dinner", icon: "flame.fill", colorHex: 0x42B883,
            kcal: 470, protein: 42, carbs: 35, fat: 16, minutes: 20, tags: ["high_protein", "low_carb", "balanced"],
            ingredients: ["180g chicken", "Mixed stir-fry veg", "Soy & ginger", "Small portion rice/noodles"],
            steps: ["Stir-fry chicken.", "Add veg and sauce.", "Serve over rice or noodles."]),
        Recipe(id: "r20", name: "Beef Chilli", category: "Dinner", icon: "flame.fill", colorHex: 0xF0A030,
            kcal: 540, protein: 40, carbs: 45, fat: 20, minutes: 35, tags: ["high_protein", "balanced"],
            ingredients: ["200g lean mince", "Kidney beans", "Chopped tomatoes", "Chilli & cumin", "Rice"],
            steps: ["Brown the mince.", "Add beans, tomatoes and spices, simmer.", "Serve with rice."]),
        Recipe(id: "r21", name: "Baked Cod & Veg", category: "Dinner", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 420, protein: 44, carbs: 25, fat: 14, minutes: 25, tags: ["mediterranean", "low_carb", "high_protein"],
            ingredients: ["200g cod", "Cherry tomatoes", "Courgette", "Olive oil & herbs", "New potatoes"],
            steps: ["Lay cod and veg on a tray.", "Drizzle oil and herbs.", "Bake 18–20 min at 200°C."]),
        Recipe(id: "r22", name: "Apple & Peanut Butter", category: "Snack", icon: "circle.fill", colorHex: 0xF0C930,
            kcal: 200, protein: 7, carbs: 25, fat: 9, minutes: 2, tags: ["clean_eating", "balanced"],
            ingredients: ["1 apple", "1 tbsp peanut butter"],
            steps: ["Slice the apple.", "Serve with peanut butter to dip."]),
        Recipe(id: "r23", name: "Cottage Cheese Bowl", category: "Snack", icon: "circle.fill", colorHex: 0x42B883,
            kcal: 190, protein: 24, carbs: 12, fat: 5, minutes: 2, tags: ["high_protein", "low_carb"],
            ingredients: ["200g cottage cheese", "Pineapple or berries", "Black pepper"],
            steps: ["Spoon cottage cheese into a bowl.", "Top with fruit."]),
        Recipe(id: "r24", name: "Edamame", category: "Snack", icon: "leaf.fill", colorHex: 0x43CB00,
            kcal: 150, protein: 13, carbs: 12, fat: 6, minutes: 5, tags: ["plant_based", "high_protein"],
            ingredients: ["150g edamame pods", "Sea salt"],
            steps: ["Steam or boil the edamame 4 min.", "Sprinkle with salt."]),
    ]

    static func by(id: String) -> Recipe? { all.first { $0.id == id } }

    /// Build a suggested day (breakfast · lunch · dinner · snack) that best fits a calorie target,
    /// preferring recipes tagged for the active plan. Deterministic given (planId, kcal).
    static func suggestedDay(planId: String?, kcalTarget: Int) -> [Recipe] {
        func pick(_ category: String, share: Double) -> Recipe? {
            let target = Double(kcalTarget) * share
            let pool = all.filter { $0.category == category }
            let matched = planId.map { p in pool.filter { $0.tags.contains(p) } } ?? []
            let candidates = matched.isEmpty ? pool : matched
            return candidates.min { abs(Double($0.kcal) - target) < abs(Double($1.kcal) - target) }
        }
        return [pick("Breakfast", share: 0.28),
                pick("Lunch", share: 0.33),
                pick("Dinner", share: 0.30),
                pick("Snack", share: 0.09)].compactMap { $0 }
    }
}
