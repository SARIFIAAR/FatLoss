import SwiftUI

enum HabitFrequency: String, Codable, CaseIterable, Hashable {
    case daily, weekly, monthly
    var title: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .daily:   "Track progress each day"
        case .weekly:  "Track across the week (Mon–Sun)"
        case .monthly: "Track across the month"
        }
    }
}

/// The catalogue of trackable metrics. `isAuto` metrics read today's value from existing app data
/// (Health / meals / workouts); the rest are logged by hand.
enum HabitMetric: String, Codable, CaseIterable, Hashable {
    case steps, floors, caloriesBurned, caloriesConsumed, protein, water
    case meditation, mood, sunExposure, sleepDuration, bedtime
    case workoutCount, workoutDistance, workoutDuration
    case checkIn                         // generic yes/no daily habit (library habits: read, journal, no sugar…)

    var title: String {
        switch self {
        case .steps: "Steps";               case .floors: "Floors Climbed"
        case .caloriesBurned: "Calories Burned"; case .caloriesConsumed: "Calories Consumed"
        case .protein: "Protein Intake";     case .water: "Hydration (Water)"
        case .meditation: "Meditation";      case .mood: "Mood"
        case .sunExposure: "Sun Exposure";   case .sleepDuration: "Sleep Duration"
        case .bedtime: "Bedtime";            case .workoutCount: "Workout Count"
        case .workoutDistance: "Workout Distance"; case .workoutDuration: "Workout Duration"
        case .checkIn: "Simple Habit"
        }
    }

    var icon: String {
        switch self {
        case .steps: "figure.walk";          case .floors: "figure.stairs"
        case .caloriesBurned: "flame.fill";  case .caloriesConsumed: "fork.knife"
        case .protein: "circle.hexagongrid.fill"; case .water: "drop.fill"
        case .meditation: "brain.head.profile"; case .mood: "face.smiling"
        case .sunExposure: "sun.max.fill";   case .sleepDuration: "bed.double.fill"
        case .bedtime: "moon.fill";          case .workoutCount: "figure.run"
        case .workoutDistance: "figure.run.circle"; case .workoutDuration: "timer"
        case .checkIn: "checkmark.circle.fill"
        }
    }

    var unit: String {
        switch self {
        case .steps: "steps";        case .floors: "floors"
        case .caloriesBurned, .caloriesConsumed: "kcal"
        case .protein: "g";          case .water: "ml"
        case .meditation, .sunExposure, .workoutDuration: "min"
        case .mood: "logs";          case .sleepDuration: "h"
        case .bedtime: "";           case .workoutCount: "workouts"
        case .workoutDistance: "km"; case .checkIn: ""
        }
    }

    var defaultGoal: Double {
        switch self {
        case .steps: 10000;   case .floors: 10
        case .caloriesBurned: 500; case .caloriesConsumed: 2000
        case .protein: 120;   case .water: 2000
        case .meditation: 10; case .mood: 1
        case .sunExposure: 15; case .sleepDuration: 8
        case .bedtime: 0;     case .workoutCount: 1
        case .workoutDistance: 5; case .workoutDuration: 30
        case .checkIn: 1
        }
    }

    var presets: [Double] {
        switch self {
        case .steps: [5000, 8000, 10000]
        case .caloriesBurned: [300, 500, 700]
        case .caloriesConsumed: [1500, 2000, 2500]
        case .protein: [80, 120, 160]
        case .water: [1500, 2000, 2500]
        case .meditation: [5, 10, 15]
        case .sunExposure: [10, 15, 30]
        case .sleepDuration: [7, 8, 9]
        case .workoutDistance: [3, 5, 10]
        case .workoutDuration: [20, 30, 45]
        default: []
        }
    }

    /// Pulled automatically from existing app data (no manual logging needed).
    var isAuto: Bool {
        switch self {
        case .steps, .caloriesBurned, .caloriesConsumed, .protein, .water,
             .sleepDuration, .workoutCount: true
        default: false
        }
    }
}

struct HabitDef: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var metric: HabitMetric
    var name: String
    var frequency: HabitFrequency = .daily
    var goal: Double
    var colorHex: UInt32 = 0x43CB00
    var createdAt: Date = Date()

    var color: Color { Color(hex: colorHex) }

    init(metric: HabitMetric, name: String? = nil, frequency: HabitFrequency = .daily,
         goal: Double? = nil, colorHex: UInt32 = 0x43CB00) {
        self.metric = metric
        self.name = name ?? metric.title
        self.frequency = frequency
        self.goal = goal ?? metric.defaultGoal
        self.colorHex = colorHex
    }

    /// Lenient decode so older/newer files never fail.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = c.value(.id, default: UUID().uuidString)
        metric    = (try? c.decode(HabitMetric.self, forKey: .metric)) ?? .steps
        name      = c.value(.name, default: metric.title)
        frequency = (try? c.decode(HabitFrequency.self, forKey: .frequency)) ?? .daily
        goal      = c.value(.goal, default: metric.defaultGoal)
        colorHex  = c.value(.colorHex, default: 0x43CB00)
        createdAt = c.value(.createdAt, default: Date(timeIntervalSince1970: 0))
    }
}

/// The eight accent colours offered when creating a habit.
enum HabitColors {
    static let all: [UInt32] = [0x43CB00, 0xF0A030, 0xF0C930, 0x4CA9E8, 0xA96CF0, 0x4C6CF0, 0xFF3B30, 0xFF3B7B]
}

/// A ready-made habit for the library picker — one tap adds a fully-configured HabitDef.
struct HabitTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let area: String
    let icon: String
    let metric: HabitMetric
    let goal: Double
    let colorHex: UInt32
    var frequency: HabitFrequency = .daily

    func makeDef() -> HabitDef {
        HabitDef(metric: metric, name: name, frequency: frequency, goal: goal, colorHex: colorHex)
    }
}

enum HabitLibrary {
    static let areas = ["Fitness", "Health", "Mind", "Productivity", "Sleep", "Nutrition", "Lifestyle"]

    static let all: [HabitTemplate] = [
        // Fitness
        .init(id: "steps", name: "Steps", area: "Fitness", icon: "figure.walk", metric: .steps, goal: 10000, colorHex: 0x43CB00),
        .init(id: "workout", name: "Workout", area: "Fitness", icon: "figure.run", metric: .workoutCount, goal: 1, colorHex: 0xFF3B30),
        .init(id: "move", name: "Move (calories)", area: "Fitness", icon: "flame.fill", metric: .caloriesBurned, goal: 500, colorHex: 0xF0A030),
        .init(id: "stretch", name: "Stretch", area: "Fitness", icon: "figure.cooldown", metric: .checkIn, goal: 1, colorHex: 0x4CA9E8),
        .init(id: "stairs", name: "Take the stairs", area: "Fitness", icon: "figure.stairs", metric: .floors, goal: 10, colorHex: 0xA96CF0),
        // Health
        .init(id: "water", name: "Drink water", area: "Health", icon: "drop.fill", metric: .water, goal: 2000, colorHex: 0x4CA9E8),
        .init(id: "vitamins", name: "Take vitamins", area: "Health", icon: "pill.fill", metric: .checkIn, goal: 1, colorHex: 0xF0A030),
        .init(id: "coldshower", name: "Cold shower", area: "Health", icon: "shower.fill", metric: .checkIn, goal: 1, colorHex: 0x4C6CF0),
        .init(id: "floss", name: "Floss", area: "Health", icon: "mouth.fill", metric: .checkIn, goal: 1, colorHex: 0x43CB00),
        .init(id: "skincare", name: "Skincare", area: "Health", icon: "sparkles", metric: .checkIn, goal: 1, colorHex: 0xFF3B7B),
        .init(id: "sun", name: "Sunlight", area: "Health", icon: "sun.max.fill", metric: .sunExposure, goal: 15, colorHex: 0xF0C930),
        // Mind
        .init(id: "meditate", name: "Meditate", area: "Mind", icon: "brain.head.profile", metric: .meditation, goal: 10, colorHex: 0xA96CF0),
        .init(id: "journal", name: "Journal", area: "Mind", icon: "book.closed.fill", metric: .checkIn, goal: 1, colorHex: 0x4C6CF0),
        .init(id: "gratitude", name: "Gratitude", area: "Mind", icon: "heart.fill", metric: .checkIn, goal: 1, colorHex: 0xFF3B7B),
        .init(id: "breathe", name: "Breathing", area: "Mind", icon: "wind", metric: .checkIn, goal: 1, colorHex: 0x4CA9E8),
        .init(id: "mood", name: "Log mood", area: "Mind", icon: "face.smiling", metric: .mood, goal: 1, colorHex: 0xF0C930),
        // Productivity
        .init(id: "read", name: "Read", area: "Productivity", icon: "book.fill", metric: .checkIn, goal: 1, colorHex: 0xF0A030),
        .init(id: "language", name: "Learn a language", area: "Productivity", icon: "character.book.closed.fill", metric: .checkIn, goal: 1, colorHex: 0x43CB00),
        .init(id: "nosocial", name: "No social media", area: "Productivity", icon: "iphone.slash", metric: .checkIn, goal: 1, colorHex: 0xFF3B30),
        .init(id: "deepwork", name: "Deep work", area: "Productivity", icon: "laptopcomputer", metric: .checkIn, goal: 1, colorHex: 0x4C6CF0),
        // Sleep
        .init(id: "sleep", name: "Sleep 8h", area: "Sleep", icon: "bed.double.fill", metric: .sleepDuration, goal: 8, colorHex: 0xA96CF0),
        .init(id: "bedtime", name: "In bed by 11", area: "Sleep", icon: "moon.fill", metric: .bedtime, goal: 0, colorHex: 0x4C6CF0),
        .init(id: "noscreens", name: "No screens before bed", area: "Sleep", icon: "iphone.slash", metric: .checkIn, goal: 1, colorHex: 0x4CA9E8),
        // Nutrition
        .init(id: "protein", name: "Hit protein", area: "Nutrition", icon: "circle.hexagongrid.fill", metric: .protein, goal: 120, colorHex: 0x43CB00),
        .init(id: "nosugar", name: "No sugar", area: "Nutrition", icon: "nosign", metric: .checkIn, goal: 1, colorHex: 0xFF3B30),
        .init(id: "noalcohol", name: "No alcohol", area: "Nutrition", icon: "nosign", metric: .checkIn, goal: 1, colorHex: 0xF0A030),
        .init(id: "veggies", name: "Eat vegetables", area: "Nutrition", icon: "leaf.fill", metric: .checkIn, goal: 1, colorHex: 0x43CB00),
        // Lifestyle
        .init(id: "family", name: "Call family", area: "Lifestyle", icon: "phone.fill", metric: .checkIn, goal: 1, colorHex: 0xF0C930, frequency: .weekly),
        .init(id: "tidy", name: "Tidy up", area: "Lifestyle", icon: "house.fill", metric: .checkIn, goal: 1, colorHex: 0x4CA9E8),
        .init(id: "dog", name: "Walk the dog", area: "Lifestyle", icon: "pawprint.fill", metric: .checkIn, goal: 1, colorHex: 0xF0A030),
    ]

    static func by(area: String) -> [HabitTemplate] { all.filter { $0.area == area } }
}
