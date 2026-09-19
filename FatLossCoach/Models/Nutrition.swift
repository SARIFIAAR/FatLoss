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
        // Eggs & dairy
        CommonFood(id: "egg", name: "Egg", serving: "1 large", icon: "circle.fill", kcal: 78, protein: 6, carbs: 0.6, fat: 5),
        CommonFood(id: "eggwhite", name: "Egg white", serving: "1", icon: "circle", kcal: 17, protein: 3.6, carbs: 0.2, fat: 0.1),
        CommonFood(id: "gyoghurt", name: "Greek yoghurt", serving: "150 g", icon: "circle.fill", kcal: 130, protein: 15, carbs: 6, fat: 5),
        CommonFood(id: "yoghurt", name: "Plain yoghurt", serving: "150 g", icon: "circle.fill", kcal: 90, protein: 8, carbs: 12, fat: 2),
        CommonFood(id: "milk", name: "Milk (whole)", serving: "1 cup", icon: "drop.fill", kcal: 122, protein: 8, carbs: 12, fat: 5),
        CommonFood(id: "skimmilk", name: "Skimmed milk", serving: "1 cup", icon: "drop", kcal: 83, protein: 8, carbs: 12, fat: 0.2),
        CommonFood(id: "cheddar", name: "Cheddar cheese", serving: "30 g", icon: "square.fill", kcal: 120, protein: 7, carbs: 0.4, fat: 10),
        CommonFood(id: "cottage", name: "Cottage cheese", serving: "100 g", icon: "circle.fill", kcal: 98, protein: 11, carbs: 3.4, fat: 4.3),
        CommonFood(id: "butter", name: "Butter", serving: "1 tbsp", icon: "square.fill", kcal: 102, protein: 0.1, carbs: 0, fat: 12),
        CommonFood(id: "feta", name: "Feta cheese", serving: "30 g", icon: "square.fill", kcal: 79, protein: 4, carbs: 1.2, fat: 6),
        // Meat & fish
        CommonFood(id: "chicken", name: "Chicken breast", serving: "100 g", icon: "fork.knife", kcal: 165, protein: 31, carbs: 0, fat: 3.6),
        CommonFood(id: "chickenthigh", name: "Chicken thigh", serving: "100 g", icon: "fork.knife", kcal: 209, protein: 26, carbs: 0, fat: 11),
        CommonFood(id: "beefmince", name: "Beef mince (lean)", serving: "100 g", icon: "fork.knife", kcal: 176, protein: 20, carbs: 0, fat: 10),
        CommonFood(id: "steak", name: "Steak (sirloin)", serving: "100 g", icon: "fork.knife", kcal: 206, protein: 27, carbs: 0, fat: 11),
        CommonFood(id: "turkey", name: "Turkey breast", serving: "100 g", icon: "fork.knife", kcal: 135, protein: 30, carbs: 0, fat: 1),
        CommonFood(id: "salmon", name: "Salmon", serving: "100 g", icon: "fish.fill", kcal: 208, protein: 20, carbs: 0, fat: 13),
        CommonFood(id: "tuna", name: "Tuna (canned)", serving: "100 g", icon: "fish.fill", kcal: 116, protein: 26, carbs: 0, fat: 1),
        CommonFood(id: "cod", name: "Cod", serving: "100 g", icon: "fish.fill", kcal: 82, protein: 18, carbs: 0, fat: 0.7),
        CommonFood(id: "prawns", name: "Prawns", serving: "100 g", icon: "fish.fill", kcal: 99, protein: 24, carbs: 0.2, fat: 0.3),
        CommonFood(id: "bacon", name: "Bacon", serving: "2 rashers", icon: "fork.knife", kcal: 108, protein: 8, carbs: 0.4, fat: 8),
        CommonFood(id: "sausage", name: "Sausage", serving: "1", icon: "fork.knife", kcal: 165, protein: 9, carbs: 3, fat: 13),
        CommonFood(id: "ham", name: "Ham", serving: "2 slices", icon: "fork.knife", kcal: 60, protein: 10, carbs: 1, fat: 2),
        // Grains & carbs
        CommonFood(id: "rice", name: "Cooked rice", serving: "1 cup", icon: "bowl.fill", kcal: 205, protein: 4.3, carbs: 45, fat: 0.4),
        CommonFood(id: "brownrice", name: "Brown rice", serving: "1 cup", icon: "bowl.fill", kcal: 216, protein: 5, carbs: 45, fat: 1.8),
        CommonFood(id: "oats", name: "Oats (dry)", serving: "50 g", icon: "bowl.fill", kcal: 190, protein: 6.5, carbs: 33, fat: 3.5),
        CommonFood(id: "pasta", name: "Cooked pasta", serving: "1 cup", icon: "bowl.fill", kcal: 220, protein: 8, carbs: 43, fat: 1.3),
        CommonFood(id: "bread", name: "Bread", serving: "1 slice", icon: "square.fill", kcal: 80, protein: 3, carbs: 15, fat: 1),
        CommonFood(id: "wholemeal", name: "Wholemeal bread", serving: "1 slice", icon: "square.fill", kcal: 82, protein: 4, carbs: 14, fat: 1.1),
        CommonFood(id: "bagel", name: "Bagel", serving: "1", icon: "circle", kcal: 245, protein: 10, carbs: 48, fat: 1.5),
        CommonFood(id: "quinoa", name: "Quinoa", serving: "1 cup", icon: "bowl.fill", kcal: 222, protein: 8, carbs: 39, fat: 3.6),
        CommonFood(id: "potato", name: "Potato", serving: "1 medium", icon: "circle.fill", kcal: 163, protein: 4.3, carbs: 37, fat: 0.2),
        CommonFood(id: "sweetpotato", name: "Sweet potato", serving: "1 medium", icon: "circle.fill", kcal: 112, protein: 2, carbs: 26, fat: 0.1),
        CommonFood(id: "tortilla", name: "Tortilla wrap", serving: "1", icon: "circle", kcal: 140, protein: 4, carbs: 24, fat: 3.5),
        CommonFood(id: "cereal", name: "Breakfast cereal", serving: "40 g", icon: "bowl.fill", kcal: 150, protein: 3, carbs: 33, fat: 1),
        CommonFood(id: "noodles", name: "Noodles", serving: "1 cup", icon: "bowl.fill", kcal: 219, protein: 7, carbs: 40, fat: 3),
        // Legumes & plant protein
        CommonFood(id: "lentils", name: "Lentils (cooked)", serving: "1 cup", icon: "leaf.fill", kcal: 230, protein: 18, carbs: 40, fat: 0.8),
        CommonFood(id: "chickpeas", name: "Chickpeas", serving: "1 cup", icon: "leaf.fill", kcal: 269, protein: 15, carbs: 45, fat: 4),
        CommonFood(id: "blackbeans", name: "Black beans", serving: "1 cup", icon: "leaf.fill", kcal: 227, protein: 15, carbs: 41, fat: 0.9),
        CommonFood(id: "tofu", name: "Tofu", serving: "100 g", icon: "leaf.fill", kcal: 76, protein: 8, carbs: 1.9, fat: 4.8),
        CommonFood(id: "edamame", name: "Edamame", serving: "100 g", icon: "leaf.fill", kcal: 121, protein: 12, carbs: 9, fat: 5),
        CommonFood(id: "hummus", name: "Hummus", serving: "2 tbsp", icon: "circle.fill", kcal: 70, protein: 2, carbs: 6, fat: 5),
        // Fruit
        CommonFood(id: "banana", name: "Banana", serving: "1 medium", icon: "leaf.fill", kcal: 105, protein: 1.3, carbs: 27, fat: 0.4),
        CommonFood(id: "apple", name: "Apple", serving: "1 medium", icon: "leaf.fill", kcal: 95, protein: 0.5, carbs: 25, fat: 0.3),
        CommonFood(id: "orange", name: "Orange", serving: "1 medium", icon: "leaf.fill", kcal: 62, protein: 1.2, carbs: 15, fat: 0.2),
        CommonFood(id: "berries", name: "Mixed berries", serving: "100 g", icon: "leaf.fill", kcal: 57, protein: 0.7, carbs: 14, fat: 0.3),
        CommonFood(id: "grapes", name: "Grapes", serving: "100 g", icon: "leaf.fill", kcal: 69, protein: 0.7, carbs: 18, fat: 0.2),
        CommonFood(id: "strawberries", name: "Strawberries", serving: "100 g", icon: "leaf.fill", kcal: 32, protein: 0.7, carbs: 8, fat: 0.3),
        CommonFood(id: "mango", name: "Mango", serving: "100 g", icon: "leaf.fill", kcal: 60, protein: 0.8, carbs: 15, fat: 0.4),
        CommonFood(id: "pineapple", name: "Pineapple", serving: "100 g", icon: "leaf.fill", kcal: 50, protein: 0.5, carbs: 13, fat: 0.1),
        CommonFood(id: "avocado", name: "Avocado", serving: "1/2", icon: "leaf.fill", kcal: 160, protein: 2, carbs: 9, fat: 15),
        CommonFood(id: "dates", name: "Dates", serving: "2", icon: "leaf.fill", kcal: 133, protein: 0.9, carbs: 36, fat: 0.1),
        // Veg
        CommonFood(id: "broccoli", name: "Broccoli", serving: "100 g", icon: "leaf.fill", kcal: 34, protein: 2.8, carbs: 7, fat: 0.4),
        CommonFood(id: "spinach", name: "Spinach", serving: "100 g", icon: "leaf.fill", kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4),
        CommonFood(id: "tomato", name: "Tomato", serving: "1 medium", icon: "leaf.fill", kcal: 22, protein: 1.1, carbs: 4.8, fat: 0.2),
        CommonFood(id: "carrot", name: "Carrot", serving: "1 medium", icon: "leaf.fill", kcal: 25, protein: 0.6, carbs: 6, fat: 0.1),
        CommonFood(id: "cucumber", name: "Cucumber", serving: "100 g", icon: "leaf.fill", kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1),
        CommonFood(id: "pepper", name: "Bell pepper", serving: "1", icon: "leaf.fill", kcal: 31, protein: 1, carbs: 7, fat: 0.3),
        CommonFood(id: "salad", name: "Mixed salad", serving: "1 bowl", icon: "leaf.fill", kcal: 20, protein: 1.5, carbs: 4, fat: 0.2),
        CommonFood(id: "sweetcorn", name: "Sweetcorn", serving: "100 g", icon: "leaf.fill", kcal: 86, protein: 3.3, carbs: 19, fat: 1.2),
        // Nuts, fats, snacks
        CommonFood(id: "almonds", name: "Almonds", serving: "28 g", icon: "circle.fill", kcal: 164, protein: 6, carbs: 6, fat: 14),
        CommonFood(id: "peanutbutter", name: "Peanut butter", serving: "1 tbsp", icon: "circle.fill", kcal: 94, protein: 4, carbs: 3, fat: 8),
        CommonFood(id: "walnuts", name: "Walnuts", serving: "28 g", icon: "circle.fill", kcal: 185, protein: 4.3, carbs: 4, fat: 18),
        CommonFood(id: "cashews", name: "Cashews", serving: "28 g", icon: "circle.fill", kcal: 157, protein: 5, carbs: 9, fat: 12),
        CommonFood(id: "oliveoil", name: "Olive oil", serving: "1 tbsp", icon: "drop.fill", kcal: 119, protein: 0, carbs: 0, fat: 14),
        CommonFood(id: "darkchoc", name: "Dark chocolate", serving: "20 g", icon: "square.fill", kcal: 120, protein: 1.5, carbs: 9, fat: 9),
        CommonFood(id: "crisps", name: "Crisps", serving: "1 bag (30 g)", icon: "bag.fill", kcal: 152, protein: 2, carbs: 15, fat: 10),
        CommonFood(id: "chocolate", name: "Milk chocolate", serving: "1 bar (45 g)", icon: "square.fill", kcal: 240, protein: 3, carbs: 26, fat: 13),
        CommonFood(id: "granolabar", name: "Granola bar", serving: "1", icon: "rectangle.fill", kcal: 130, protein: 3, carbs: 18, fat: 5),
        CommonFood(id: "ricecake", name: "Rice cake", serving: "1", icon: "circle", kcal: 35, protein: 0.7, carbs: 7.3, fat: 0.3),
        // Drinks & staples
        CommonFood(id: "coffee", name: "Coffee (black)", serving: "1 cup", icon: "cup.and.saucer.fill", kcal: 2, protein: 0.3, carbs: 0, fat: 0),
        CommonFood(id: "latte", name: "Latte", serving: "1 medium", icon: "cup.and.saucer.fill", kcal: 120, protein: 6, carbs: 10, fat: 6),
        CommonFood(id: "tea", name: "Tea (with milk)", serving: "1 cup", icon: "cup.and.saucer.fill", kcal: 30, protein: 1.5, carbs: 3, fat: 1),
        CommonFood(id: "orangejuice", name: "Orange juice", serving: "1 cup", icon: "drop.fill", kcal: 112, protein: 1.7, carbs: 26, fat: 0.5),
        CommonFood(id: "protein", name: "Protein shake", serving: "1 scoop", icon: "bolt.fill", kcal: 120, protein: 24, carbs: 3, fat: 1.5),
        CommonFood(id: "beer", name: "Beer", serving: "1 pint", icon: "drop.fill", kcal: 208, protein: 2, carbs: 18, fat: 0),
        CommonFood(id: "wine", name: "Wine", serving: "1 glass", icon: "drop.fill", kcal: 125, protein: 0.1, carbs: 4, fat: 0),
        CommonFood(id: "honey", name: "Honey", serving: "1 tbsp", icon: "drop.fill", kcal: 64, protein: 0.1, carbs: 17, fat: 0),
        // Common meals
        CommonFood(id: "pizza", name: "Pizza slice", serving: "1 slice", icon: "triangle.fill", kcal: 285, protein: 12, carbs: 36, fat: 10),
        CommonFood(id: "burger", name: "Cheeseburger", serving: "1", icon: "circle.fill", kcal: 303, protein: 15, carbs: 33, fat: 14),
        CommonFood(id: "sandwich", name: "Chicken sandwich", serving: "1", icon: "square.fill", kcal: 350, protein: 25, carbs: 35, fat: 12),
        CommonFood(id: "fries", name: "Fries", serving: "1 medium", icon: "rectangle.fill", kcal: 365, protein: 4, carbs: 48, fat: 17),
        CommonFood(id: "sushi", name: "Sushi roll", serving: "6 pieces", icon: "circle.fill", kcal: 255, protein: 9, carbs: 38, fat: 7),
        CommonFood(id: "soup", name: "Vegetable soup", serving: "1 bowl", icon: "bowl.fill", kcal: 120, protein: 4, carbs: 20, fat: 3),
        CommonFood(id: "omelette", name: "Omelette (2 egg)", serving: "1", icon: "circle.fill", kcal: 220, protein: 14, carbs: 2, fat: 17),
        CommonFood(id: "porridge", name: "Porridge", serving: "1 bowl", icon: "bowl.fill", kcal: 220, protein: 8, carbs: 33, fat: 5),
    ]

    /// Local, offline substring search over the curated set + the bundled USDA core (~1,200 foods).
    static func search(_ query: String) -> [CommonFood] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let curated = all.filter { $0.name.lowercased().contains(q) }
        var seen = Set(curated.map { $0.name.lowercased() })
        var out = curated
        for f in BundledFoods.all where f.name.lowercased().contains(q) && !seen.contains(f.name.lowercased()) {
            out.append(f); seen.insert(f.name.lowercased())
            if out.count >= 30 { break }
        }
        return out
    }
}

/// The USDA core (public domain) bundled for instant offline search — built by server/build-fooddb.mjs
/// into Resources/core-foods.json (per-100g macros incl. fibre/sugar/sodium/sat-fat).
enum BundledFoods {
    struct Raw: Decodable {
        let id: String; let name: String
        let kcal: Double; let protein: Double; let carbs: Double; let fat: Double
        let fibre: Double?; let sugar: Double?; let sodium: Double?; let satFat: Double?
    }
    static let all: [CommonFood] = {
        guard let url = Bundle.main.url(forResource: "core-foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return rows.map {
            CommonFood(id: "core-\($0.id)", name: $0.name, serving: "100 g", icon: "fork.knife",
                       kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
        }
    }()
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
        Recipe(id: "r25", name: "Shakshuka", category: "Breakfast", icon: "flame.fill", colorHex: 0xF0A030,
            kcal: 320, protein: 18, carbs: 20, fat: 20, minutes: 20, tags: ["mediterranean", "clean_eating"],
            ingredients: ["2 eggs", "Chopped tomatoes", "Onion & pepper", "Paprika & cumin", "Olive oil"],
            steps: ["Soften onion & pepper.", "Add tomatoes & spices, simmer.", "Crack in eggs, cook until set."]),
        Recipe(id: "r26", name: "Overnight Oats", category: "Breakfast", icon: "bowl.fill", colorHex: 0x42B883,
            kcal: 350, protein: 15, carbs: 50, fat: 9, minutes: 5, tags: ["balanced", "clean_eating"],
            ingredients: ["50g oats", "150ml milk", "Greek yoghurt", "Chia seeds", "Berries"],
            steps: ["Mix oats, milk, yoghurt, chia.", "Chill overnight.", "Top with berries."]),
        Recipe(id: "r27", name: "Breakfast Burrito", category: "Breakfast", icon: "fork.knife", colorHex: 0xF0C930,
            kcal: 420, protein: 24, carbs: 38, fat: 20, minutes: 15, tags: ["high_protein", "balanced"],
            ingredients: ["Tortilla", "2 eggs", "Black beans", "Cheese", "Salsa"],
            steps: ["Scramble eggs.", "Warm beans.", "Fill tortilla, roll and toast."]),
        Recipe(id: "r28", name: "Green Smoothie", category: "Breakfast", icon: "drop.fill", colorHex: 0x43CB00,
            kcal: 240, protein: 20, carbs: 32, fat: 4, minutes: 5, tags: ["plant_based", "high_protein"],
            ingredients: ["Spinach", "Banana", "Protein powder", "Almond milk", "Peanut butter"],
            steps: ["Add everything to a blender.", "Blend until smooth."]),
        Recipe(id: "r29", name: "Caprese Salad", category: "Lunch", icon: "leaf.circle.fill", colorHex: 0x0093E7,
            kcal: 320, protein: 16, carbs: 8, fat: 25, minutes: 8, tags: ["mediterranean", "low_carb"],
            ingredients: ["Mozzarella", "Tomatoes", "Basil", "Olive oil", "Balsamic"],
            steps: ["Slice mozzarella & tomato.", "Layer with basil.", "Drizzle oil & balsamic."]),
        Recipe(id: "r30", name: "Falafel Wrap", category: "Lunch", icon: "fork.knife", colorHex: 0xA96CF0,
            kcal: 480, protein: 18, carbs: 58, fat: 20, minutes: 15, tags: ["plant_based", "mediterranean"],
            ingredients: ["Falafel", "Flatbread", "Hummus", "Salad", "Tahini"],
            steps: ["Warm falafel.", "Spread hummus on bread.", "Fill with falafel & salad."]),
        Recipe(id: "r31", name: "Chicken Caesar", category: "Lunch", icon: "leaf.circle.fill", colorHex: 0x42B883,
            kcal: 430, protein: 40, carbs: 15, fat: 24, minutes: 15, tags: ["high_protein", "low_carb"],
            ingredients: ["Chicken breast", "Romaine", "Parmesan", "Caesar dressing", "Croutons"],
            steps: ["Grill chicken.", "Toss lettuce with dressing.", "Top with chicken & parmesan."]),
        Recipe(id: "r32", name: "Sushi Bowl", category: "Lunch", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 520, protein: 32, carbs: 58, fat: 16, minutes: 20, tags: ["balanced", "high_protein"],
            ingredients: ["Rice", "Salmon or tuna", "Cucumber", "Avocado", "Soy & sesame"],
            steps: ["Cube fish.", "Build over rice.", "Add veg & sauce."]),
        Recipe(id: "r33", name: "Minestrone", category: "Lunch", icon: "bowl.fill", colorHex: 0xF0A030,
            kcal: 320, protein: 14, carbs: 50, fat: 7, minutes: 30, tags: ["mediterranean", "plant_based"],
            ingredients: ["Mixed veg", "Cannellini beans", "Pasta", "Tomato", "Stock"],
            steps: ["Soften veg.", "Add tomato & stock.", "Add beans & pasta, simmer."]),
        Recipe(id: "r34", name: "Turkey Meatballs", category: "Dinner", icon: "flame.fill", colorHex: 0x42B883,
            kcal: 460, protein: 42, carbs: 30, fat: 18, minutes: 30, tags: ["high_protein", "balanced"],
            ingredients: ["Turkey mince", "Egg & breadcrumb", "Tomato sauce", "Courgetti or pasta"],
            steps: ["Form & bake meatballs.", "Simmer in sauce.", "Serve over courgetti/pasta."]),
        Recipe(id: "r35", name: "Thai Green Curry", category: "Dinner", icon: "flame.fill", colorHex: 0x43CB00,
            kcal: 540, protein: 32, carbs: 45, fat: 24, minutes: 30, tags: ["balanced"],
            ingredients: ["Chicken or tofu", "Green curry paste", "Coconut milk", "Veg", "Rice"],
            steps: ["Fry paste.", "Add protein & coconut milk.", "Add veg, serve with rice."]),
        Recipe(id: "r36", name: "Stuffed Peppers", category: "Dinner", icon: "leaf.fill", colorHex: 0xF0A030,
            kcal: 400, protein: 24, carbs: 42, fat: 14, minutes: 40, tags: ["balanced", "clean_eating"],
            ingredients: ["Bell peppers", "Lean mince or lentils", "Rice", "Tomato", "Cheese"],
            steps: ["Halve & deseed peppers.", "Fill with mince & rice.", "Bake 30 min."]),
        Recipe(id: "r37", name: "Roast Chicken Dinner", category: "Dinner", icon: "fork.knife", colorHex: 0x42B883,
            kcal: 560, protein: 45, carbs: 40, fat: 24, minutes: 45, tags: ["high_protein", "balanced"],
            ingredients: ["Chicken", "Potatoes", "Carrots & greens", "Olive oil", "Herbs"],
            steps: ["Roast chicken & potatoes.", "Steam greens.", "Plate with gravy."]),
        Recipe(id: "r38", name: "Prawn Stir-fry", category: "Dinner", icon: "fish.fill", colorHex: 0x0093E7,
            kcal: 380, protein: 30, carbs: 35, fat: 12, minutes: 15, tags: ["low_carb", "high_protein"],
            ingredients: ["Prawns", "Mixed veg", "Garlic & ginger", "Soy", "Noodles or rice"],
            steps: ["Fry prawns.", "Add veg & sauce.", "Toss with noodles."]),
        Recipe(id: "r39", name: "Veggie Chilli", category: "Dinner", icon: "flame.fill", colorHex: 0x43CB00,
            kcal: 420, protein: 18, carbs: 65, fat: 9, minutes: 35, tags: ["plant_based", "clean_eating"],
            ingredients: ["Mixed beans", "Tomato", "Peppers & onion", "Spices", "Rice"],
            steps: ["Soften veg.", "Add beans, tomato & spices.", "Simmer, serve with rice."]),
        Recipe(id: "r40", name: "Cauliflower Curry", category: "Dinner", icon: "leaf.fill", colorHex: 0xA96CF0,
            kcal: 360, protein: 12, carbs: 40, fat: 18, minutes: 30, tags: ["plant_based", "low_carb"],
            ingredients: ["Cauliflower", "Chickpeas", "Coconut milk", "Curry spices", "Spinach"],
            steps: ["Roast cauliflower.", "Simmer in spiced coconut milk.", "Stir in spinach."]),
        Recipe(id: "r41", name: "Boiled Eggs", category: "Snack", icon: "circle.fill", colorHex: 0xF0C930,
            kcal: 155, protein: 13, carbs: 1, fat: 11, minutes: 10, tags: ["low_carb", "high_protein"],
            ingredients: ["2 eggs", "Salt & pepper"],
            steps: ["Boil eggs 7 min.", "Cool, peel, season."]),
        Recipe(id: "r42", name: "Trail Mix", category: "Snack", icon: "circle.fill", colorHex: 0xF0A030,
            kcal: 210, protein: 6, carbs: 18, fat: 14, minutes: 1, tags: ["balanced"],
            ingredients: ["Mixed nuts", "Raisins", "Dark choc chips"],
            steps: ["Combine and portion into 30g servings."]),
        Recipe(id: "r43", name: "Rice Cakes & PB", category: "Snack", icon: "circle", colorHex: 0x42B883,
            kcal: 180, protein: 6, carbs: 20, fat: 9, minutes: 2, tags: ["clean_eating", "balanced"],
            ingredients: ["2 rice cakes", "1 tbsp peanut butter", "Banana slices"],
            steps: ["Spread PB on rice cakes.", "Top with banana."]),
        Recipe(id: "r44", name: "Protein Yoghurt Bowl", category: "Snack", icon: "circle.fill", colorHex: 0x42B883,
            kcal: 230, protein: 24, carbs: 20, fat: 5, minutes: 3, tags: ["high_protein", "low_carb"],
            ingredients: ["Greek yoghurt", "Whey scoop", "Berries", "Granola"],
            steps: ["Stir whey into yoghurt.", "Top with berries & granola."]),
        Recipe(id: "r45", name: "Guac & Veg", category: "Snack", icon: "leaf.circle.fill", colorHex: 0x43CB00,
            kcal: 180, protein: 3, carbs: 14, fat: 13, minutes: 5, tags: ["plant_based", "low_carb"],
            ingredients: ["Avocado", "Lime & salt", "Carrot & pepper sticks"],
            steps: ["Mash avocado with lime & salt.", "Serve with veg sticks."]),
        Recipe(id: "r46", name: "Cheese & Crackers", category: "Snack", icon: "square.fill", colorHex: 0xF0C930,
            kcal: 220, protein: 9, carbs: 18, fat: 12, minutes: 2, tags: ["balanced"],
            ingredients: ["Wholegrain crackers", "Cheddar", "Grapes"],
            steps: ["Slice cheese.", "Serve with crackers & grapes."]),
        Recipe(id: "r47", name: "Banana Protein Muffin", category: "Snack", icon: "circle.fill", colorHex: 0xA96CF0,
            kcal: 160, protein: 10, carbs: 20, fat: 5, minutes: 20, tags: ["high_protein", "clean_eating"],
            ingredients: ["Banana", "Oats", "Egg", "Whey", "Baking powder"],
            steps: ["Blend to a batter.", "Bake in muffin tin 15 min at 180°C."]),
        Recipe(id: "r48", name: "Miso Soup", category: "Snack", icon: "bowl.fill", colorHex: 0x0093E7,
            kcal: 90, protein: 6, carbs: 8, fat: 3, minutes: 8, tags: ["plant_based", "low_carb"],
            ingredients: ["Miso paste", "Tofu", "Spring onion", "Seaweed"],
            steps: ["Dissolve miso in hot water.", "Add tofu & seaweed."]),
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
