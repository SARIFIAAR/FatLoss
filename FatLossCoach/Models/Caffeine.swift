import SwiftUI

/// A logged caffeinated drink — stored as espresso-shot equivalents + caffeine mg + time.
/// Kept separate from meals (this is a health/recovery signal, not a calorie entry).
struct CaffeineEntry: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var date: String
    var time: Date = Date()
    var name: String
    var shots: Double      // espresso shots (or shot-equivalents for brewed)
    var mg: Double         // caffeine, mg

    init(date: String, name: String, shots: Double, mg: Double) {
        self.date = date; self.name = name; self.shots = shots; self.mg = mg
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID().uuidString)
        date = c.value(.date, default: DateKey.key())
        time = c.value(.time, default: Date())
        name = c.value(.name, default: "Coffee")
        shots = c.value(.shots, default: 1)
        mg = c.value(.mg, default: 75)
    }
}

/// A coffee preset — Starbucks-style sizes map to a shot count + caffeine, plus a few brewed options.
struct CoffeePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let shots: Double
    let mg: Double
}

enum CoffeeCatalog {
    /// Espresso-based drinks: size → shots (the Starbucks model), + brewed cups measured as shot-equivalents.
    static let all: [CoffeePreset] = [
        CoffeePreset(id: "espresso",    name: "Espresso",        icon: "cup.and.saucer.fill", shots: 1, mg: 63),
        CoffeePreset(id: "double",      name: "Double Espresso", icon: "cup.and.saucer.fill", shots: 2, mg: 126),
        CoffeePreset(id: "tall",        name: "Tall (12oz)",     icon: "cup.and.saucer.fill", shots: 1, mg: 75),
        CoffeePreset(id: "grande",      name: "Grande (16oz)",   icon: "cup.and.saucer.fill", shots: 2, mg: 150),
        CoffeePreset(id: "venti",       name: "Venti (20oz)",    icon: "cup.and.saucer.fill", shots: 2, mg: 150),
        CoffeePreset(id: "venti_iced",  name: "Venti Iced",      icon: "cup.and.saucer.fill", shots: 3, mg: 225),
        CoffeePreset(id: "americano_g", name: "Grande Americano", icon: "cup.and.saucer.fill", shots: 3, mg: 225),
        CoffeePreset(id: "flatwhite",   name: "Flat White",      icon: "cup.and.saucer.fill", shots: 2, mg: 130),
        CoffeePreset(id: "drip",        name: "Brewed / Drip",   icon: "cup.and.saucer",      shots: 1.5, mg: 120),
        CoffeePreset(id: "instant",     name: "Instant",         icon: "cup.and.saucer",      shots: 1, mg: 65),
        CoffeePreset(id: "cold_brew",   name: "Cold Brew",       icon: "cup.and.saucer",      shots: 2.5, mg: 200),
        CoffeePreset(id: "tea",         name: "Tea",             icon: "leaf.fill",           shots: 0.5, mg: 40),
        CoffeePreset(id: "energy",      name: "Energy Drink",    icon: "bolt.fill",           shots: 2, mg: 160),
        CoffeePreset(id: "decaf",       name: "Decaf",           icon: "cup.and.saucer",      shots: 1, mg: 3),
    ]
}
