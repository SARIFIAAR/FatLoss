import SwiftUI

/// A logged caffeinated drink — stored as espresso-shot equivalents + caffeine mg + time.
/// Milk-based drinks also carry calories and spawn a linked meal entry (see `mealId`) so they
/// count in Nutrition automatically; black coffee (0 kcal) stays a pure caffeine signal.
struct CaffeineEntry: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var date: String
    var time: Date = Date()
    var name: String
    var shots: Double      // espresso shots (or shot-equivalents for brewed)
    var mg: Double         // caffeine, mg
    var kcal: Double = 0   // calories (milk/syrup drinks); 0 for black coffee
    var mealId: String? = nil   // id of the linked MealEntry in Nutrition, when kcal > 0

    init(date: String, name: String, shots: Double, mg: Double, kcal: Double = 0, mealId: String? = nil) {
        self.date = date; self.name = name; self.shots = shots; self.mg = mg
        self.kcal = kcal; self.mealId = mealId
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID().uuidString)
        date = c.value(.date, default: DateKey.key())
        time = c.value(.time, default: Date())
        name = c.value(.name, default: "Coffee")
        shots = c.value(.shots, default: 1)
        mg = c.value(.mg, default: 75)
        kcal = c.value(.kcal, default: 0)
        mealId = c.value(.mealId, default: nil)
    }
}

/// A coffee preset — Starbucks-style sizes map to a shot count + caffeine, plus calories/macros
/// for milk-based drinks so logging one also updates the day's nutrition.
struct CoffeePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let shots: Double
    let mg: Double
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
}

enum CoffeeCatalog {
    /// Black / espresso-based drinks — caffeine only, ~0 calories.
    static let black: [CoffeePreset] = [
        CoffeePreset(id: "espresso",    name: "Espresso",         icon: "cup.and.saucer.fill", shots: 1,   mg: 63),
        CoffeePreset(id: "double",      name: "Double Espresso",  icon: "cup.and.saucer.fill", shots: 2,   mg: 126),
        CoffeePreset(id: "americano_g", name: "Americano",        icon: "cup.and.saucer.fill", shots: 3,   mg: 225, kcal: 15, protein: 1, carbs: 2, fat: 0),
        CoffeePreset(id: "drip",        name: "Brewed / Drip",    icon: "cup.and.saucer",      shots: 1.5, mg: 120, kcal: 5),
        CoffeePreset(id: "cold_brew",   name: "Cold Brew",        icon: "cup.and.saucer",      shots: 2.5, mg: 200, kcal: 5),
        CoffeePreset(id: "instant",     name: "Instant",          icon: "cup.and.saucer",      shots: 1,   mg: 65,  kcal: 5),
        CoffeePreset(id: "decaf",       name: "Decaf",            icon: "cup.and.saucer",      shots: 1,   mg: 3),
    ]

    /// Milk / syrup drinks — carry calories, so they also log to Nutrition (grande / regular size).
    static let milk: [CoffeePreset] = [
        CoffeePreset(id: "cappuccino",  name: "Cappuccino",       icon: "cup.and.saucer.fill", shots: 2, mg: 150, kcal: 130, protein: 8,  carbs: 12, fat: 6),
        CoffeePreset(id: "latte",       name: "Latte",            icon: "cup.and.saucer.fill", shots: 2, mg: 150, kcal: 190, protein: 12, carbs: 19, fat: 7),
        CoffeePreset(id: "flatwhite",   name: "Flat White",       icon: "cup.and.saucer.fill", shots: 2, mg: 130, kcal: 170, protein: 11, carbs: 16, fat: 8),
        CoffeePreset(id: "cortado",     name: "Cortado",          icon: "cup.and.saucer.fill", shots: 2, mg: 130, kcal: 80,  protein: 5,  carbs: 6,  fat: 4),
        CoffeePreset(id: "macchiato",   name: "Latte Macchiato",  icon: "cup.and.saucer.fill", shots: 2, mg: 150, kcal: 190, protein: 12, carbs: 18, fat: 7),
        CoffeePreset(id: "caramel_mac", name: "Caramel Macchiato",icon: "cup.and.saucer.fill", shots: 2, mg: 150, kcal: 250, protein: 10, carbs: 35, fat: 7),
        CoffeePreset(id: "mocha",       name: "Mocha",            icon: "cup.and.saucer.fill", shots: 2, mg: 175, kcal: 290, protein: 13, carbs: 40, fat: 9),
        CoffeePreset(id: "iced_latte",  name: "Iced Latte",       icon: "cup.and.saucer.fill", shots: 2, mg: 150, kcal: 130, protein: 8,  carbs: 13, fat: 5),
    ]

    /// Other caffeine sources.
    static let other: [CoffeePreset] = [
        CoffeePreset(id: "tea",         name: "Tea",              icon: "leaf.fill",           shots: 0.5, mg: 40),
        CoffeePreset(id: "matcha",      name: "Matcha Latte",     icon: "leaf.fill",           shots: 1,   mg: 70,  kcal: 190, protein: 8, carbs: 30, fat: 5),
        CoffeePreset(id: "energy",      name: "Energy Drink",     icon: "bolt.fill",           shots: 2,   mg: 160, kcal: 110, carbs: 28),
    ]

    static let all: [CoffeePreset] = black + milk + other

    /// Named sections for the picker.
    static let sections: [(title: String, items: [CoffeePreset])] = [
        ("Black coffee", black), ("With milk", milk), ("Other", other),
    ]
}
