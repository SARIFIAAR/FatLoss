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

    var title: String {
        switch self {
        case .steps: "Steps";               case .floors: "Floors Climbed"
        case .caloriesBurned: "Calories Burned"; case .caloriesConsumed: "Calories Consumed"
        case .protein: "Protein Intake";     case .water: "Hydration (Water)"
        case .meditation: "Meditation";      case .mood: "Mood"
        case .sunExposure: "Sun Exposure";   case .sleepDuration: "Sleep Duration"
        case .bedtime: "Bedtime";            case .workoutCount: "Workout Count"
        case .workoutDistance: "Workout Distance"; case .workoutDuration: "Workout Duration"
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
        case .workoutDistance: "km"
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
