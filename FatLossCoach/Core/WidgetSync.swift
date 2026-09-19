import Foundation
import WidgetKit

/// App Group shared by the app and the HumansWidget extension. Both read/write one small JSON
/// snapshot of the day's headline body KPIs so the home-screen widget never touches HealthKit.
let humansAppGroupID = "group.com.MyFatLossCoach.app"
let humansWidgetFile = "humans-widget.json"

/// The tiny payload the widget renders. Mirrored (by field name) in the widget target's own copy.
struct HumansWidgetData: Codable {
    var score: Int?             // synthesized HUMANS Score 0–100
    var scoreLabel: String = "—"
    var recovery: Int?          // 0–100
    var recoveryLabel: String
    var strain: Double          // 0–21
    var strainLabel: String
    var sleepPct: Int?          // sleep performance %
    var sleepHours: Double?
    var battery: Int?           // body battery 0–100
    var stress: Int?            // 0–100
    var updated: Date

    static let placeholder = HumansWidgetData(
        score: 78, scoreLabel: "Strong", recovery: 72, recoveryLabel: "Balanced", strain: 11.4, strainLabel: "Moderate",
        sleepPct: 88, sleepHours: 7.4, battery: 64, stress: 30, updated: .now)
}

enum WidgetSync {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: humansAppGroupID)?
            .appendingPathComponent(humansWidgetFile)
    }

    /// Compute today's headline scores and hand them to the widget. Cheap; safe to call on every save.
    static func publish(from store: Store) {
        guard let url = fileURL else { return }   // App Group not provisioned (e.g. plain sim run)
        let s = store.bodyDay()
        let data = HumansWidgetData(
            score: s.humansScore,
            scoreLabel: s.humansScoreLabel,
            recovery: s.recovery?.score,
            recoveryLabel: recoveryLabel(s.recovery?.score),
            strain: s.strain.score,
            strainLabel: strainLabel(s.strain.score),
            sleepPct: s.sleepPerformance.map { Int($0.rounded()) },
            sleepHours: s.day.sleepH,
            battery: s.battery?.level,
            stress: s.stress?.score,
            updated: .now)
        if let raw = try? encoder.encode(data) {
            try? raw.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func recoveryLabel(_ score: Int?) -> String {
        guard let s = score else { return "—" }
        return s >= 67 ? "Recovered" : s >= 34 ? "Balanced" : "Low"
    }
    static func strainLabel(_ score: Double) -> String {
        switch score {
        case ..<8:   return "Light"
        case ..<14:  return "Moderate"
        case ..<18:  return "High"
        default:     return "All out"
        }
    }
}
