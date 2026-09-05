import Foundation

/// Imports a `JSON.stringify(localStorage)` dump from the original web app (My Fitness Coach HTML).
/// Keys handled: weight-logs, cur-weight, waist-logs, cur-waist, rec-YYYY-MM-DD, po-{Exercise},
/// habits-YYYY-MM-DD, supps-YYYY-MM-DD, water-YYYY-MM-DD, health-sync, ex-YYYY-MM-DD-Day, mood-YYYY-MM-DD.
extension Store {
    enum ImportError: LocalizedError {
        case invalidJSON
        var errorDescription: String? {
            "Couldn't read that JSON. In the web app open Profile → “Copy my data”, then paste here."
        }
    }

    @discardableResult
    func importLegacy(_ text: String) throws -> Int {
        guard let raw = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw ImportError.invalidJSON
        }
        var count = 0
        // Process derived keys last so they never shadow real logs.
        let ordered = obj.keys.sorted { a, b in
            let da = a.hasPrefix("cur-"), db = b.hasPrefix("cur-")
            return da == db ? a < b : !da
        }
        for key in ordered {
            let value = Self.unwrap(obj[key] as Any)
            if applyLegacy(key: key, value: value) { count += 1 }
        }
        if count > 0 { showToast("Imported \(count) records ✓") }
        return count
    }

    /// localStorage values are JSON-encoded strings; decode them if so.
    private static func unwrap(_ v: Any) -> Any {
        if let s = v as? String, let d = s.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) {
            return parsed
        }
        return v
    }

    private func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Fmt.parse(s) }
        return nil
    }

    private func truthy(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.doubleValue != 0 }
        return false
    }

    private func applyLegacy(key: String, value: Any) -> Bool {
        switch key {
        case "weight-logs", "waist-logs":
            guard let arr = value as? [[String: Any]] else { return false }
            let field = key == "weight-logs" ? "weight" : "waist"
            for e in arr {
                guard let d = e["date"] as? String, let v = num(e[field]) else { continue }
                if key == "weight-logs" { upsert(&data.weightLogs, date: d, value: v) }
                else { upsert(&data.waistLogs, date: d, value: v) }
            }
            return true

        case "cur-weight":
            if data.weightLogs.isEmpty, let v = num(value) { upsert(&data.weightLogs, date: today, value: v) }
            return true

        case "cur-waist":
            if data.waistLogs.isEmpty, let v = num(value) { upsert(&data.waistLogs, date: today, value: v) }
            return true

        case "health-sync":
            guard let arr = value as? [[String: Any]] else { return false }
            for e in arr {
                guard let d = e["date"] as? String else { continue }
                setHealth(steps: num(e["steps"]).map { Int($0) }, restingHR: num(e["resting_hr"]), on: d)
            }
            return true

        default:
            break
        }

        if key.hasPrefix("rec-") {
            let day = String(key.dropFirst(4))
            guard let dict = value as? [String: Any] else { return false }
            updateRecovery(on: day) { r in
                if let v = num(dict["hrv"]), v > 0 { r.hrv = v }
                if let v = num(dict["rhr"]), v > 0 { r.rhr = v }
                if let v = num(dict["sleep_h"]), v > 0 { r.sleepH = v }
                if let v = num(dict["deep_h"]), v > 0 { r.deepH = v }
                if let v = num(dict["rem_h"]), v > 0 { r.remH = v }
                if let v = num(dict["resp"]), v > 0 { r.resp = v }
                if let v = num(dict["mood"]), v > 0 { r.mood = Int(v) }
            }
            return true
        }
        if key.hasPrefix("mood-") {
            let day = String(key.dropFirst(5))
            guard let v = num(value), v > 0 else { return false }
            updateRecovery(on: day) { if $0.mood == nil { $0.mood = Int(v) } }
            return true
        }
        if key.hasPrefix("po-") {
            let name = String(key.dropFirst(3))
            guard let arr = value as? [[String: Any]] else { return false }
            for e in arr {
                guard let d = e["date"] as? String, let kg = num(e["kg"]), let reps = num(e["reps"]) else { continue }
                saveExerciseLog(name, kg: kg, reps: Int(reps), on: d)
            }
            return true
        }
        if key.hasPrefix("habits-") || key.hasPrefix("supps-") {
            let isHabit = key.hasPrefix("habits-")
            let day = String(key.dropFirst(isHabit ? 7 : 6))
            guard let dict = value as? [String: Any] else { return false }
            let done = Set(dict.filter { truthy($0.value) }.keys)
            if isHabit { data.habits[day] = (data.habits[day] ?? []).union(done) }
            else { data.supplements[day] = (data.supplements[day] ?? []).union(done) }
            return true
        }
        if key.hasPrefix("water-") {
            let day = String(key.dropFirst(6))
            guard let v = num(value) else { return false }
            data.water[day] = max(data.water[day] ?? 0, Int(v))
            return true
        }
        if key.hasPrefix("ex-") {
            // ex-2026-09-06-Mon
            let rest = String(key.dropFirst(3))
            guard rest.count > 11, let dict = value as? [String: Any] else { return false }
            let day = String(rest.prefix(10))
            let weekday = String(rest.dropFirst(11))
            let idx = Set(dict.filter { truthy($0.value) }.keys.compactMap { Int($0) })
            let k = "\(day)-\(weekday)"
            data.exerciseDone[k] = (data.exerciseDone[k] ?? []).union(idx)
            return true
        }
        return false
    }
}
