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

    var color: Color { Color(hex: colorHex) }

    /// Macro grams for a given daily calorie goal, from this plan's split.
    func macros(forKcal kcal: Int) -> (protein: Int, carbs: Int, fat: Int) {
        let p = Double(kcal) * Double(proteinPct) / 100 / 4
        let c = Double(kcal) * Double(carbPct) / 100 / 4
        let f = Double(kcal) * Double(fatPct) / 100 / 9
        return (Int(p.rounded()), Int(c.rounded()), Int(f.rounded()))
    }
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
    ]

    static func by(id: String?) -> DietProgram? { all.first { $0.id == id } }
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
    ]

    static func by(id: String) -> Recipe? { all.first { $0.id == id } }
}
