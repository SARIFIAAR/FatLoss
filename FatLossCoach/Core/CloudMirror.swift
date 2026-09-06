import Foundation
import CryptoKit
import UIKit
import FirebaseFirestore

/// Flattens `AppData` into query-friendly Firestore rows so every data point can be trended per user
/// from the backend (Firebase console, the Fly.io admin dashboard, exports):
///
///     users/{uid}                  profile · goals · programme · summary stats (merged next to the "json" blob)
///     users/{uid}/days/{date}      one wide row per day with every metric tracked that day
///     users/{uid}/meals/{mealId}   one row per logged meal, including the scanned items
///
/// Only rows whose content changed since the last push are written (a SHA-256 of each row is cached
/// per user in UserDefaults), so a normal day costs a handful of writes, well inside the free quota.
final class CloudMirror {
    static let schema = 2

    private var hashes: [String: String] = [:]      // "days/2026-09-06" → row hash
    private var hashesUID: String?

    // MARK: Public

    /// Writes changed day/meal rows for `uid` and returns how many documents were written or deleted.
    @discardableResult
    func push(uid: String, data: AppData) async throws -> Int {
        loadCache(uid)
        let db = Firestore.firestore()
        let user = db.collection("users").document(uid)

        var rows: [String: [String: Any]] = [:]
        for (date, row) in Self.dayRows(data) { rows["days/\(date)"] = row }
        for (id, row) in Self.mealRows(data) { rows["meals/\(id)"] = row }

        var ops: [(path: String, row: [String: Any]?)] = []
        for (path, row) in rows where hashes[path] != Self.hash(row) { ops.append((path, row)) }
        for path in hashes.keys where rows[path] == nil { ops.append((path, nil)) }
        guard !ops.isEmpty else { return 0 }

        let now = Timestamp(date: Date())
        for chunk in stride(from: 0, to: ops.count, by: 400).map({ Array(ops[$0..<min($0 + 400, ops.count)]) }) {
            let batch = db.batch()
            for op in chunk {
                let parts = op.path.split(separator: "/", maxSplits: 1).map(String.init)
                let ref = user.collection(parts[0]).document(parts[1])
                if var row = op.row {
                    row["updatedAt"] = now
                    batch.setData(row, forDocument: ref)
                } else {
                    batch.deleteDocument(ref)
                }
            }
            try await batch.commit()
            for op in chunk {
                if let row = op.row { hashes[op.path] = Self.hash(row) } else { hashes.removeValue(forKey: op.path) }
            }
            saveCache(uid)
        }
        return ops.count
    }

    /// Fields merged into `users/{uid}` next to the JSON blob.
    static func profileFields(data: AppData, displayName: String?, email: String?, isNew: Bool) -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var profile: [String: Any] = [
            "displayName": displayName ?? NSNull(),
            "email": email ?? NSNull(),
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "device": UIDevice.current.model,
            "os": "iOS " + UIDevice.current.systemVersion,
            "timezone": TimeZone.current.identifier,
            "lastSeenAt": FieldValue.serverTimestamp(),
        ]
        if isNew { profile["createdAt"] = FieldValue.serverTimestamp() }

        let g = data.goals
        let goals: [String: Any] = [
            "startWeight": g.startWeight, "goalWeight": g.goalWeight, "waistTarget": g.waistTarget,
            "stepsGoal": g.stepsGoal, "waterGoal": g.waterGoal, "kcal": g.kcal, "protein": g.protein,
            "carbs": g.carbs, "fat": g.fat, "deficit": g.deficit,
        ]
        let program: [String: Any] = ["phase": data.program.phase, "startDate": data.program.startDate ?? NSNull()]

        let latestW = data.weightLogs.max { $0.date < $1.date }
        let latestWaist = data.waistLogs.max { $0.date < $1.date }
        let days = dayRows(data)
        let mealCount = data.meals.values.reduce(0) { $0 + $1.count }
        let lastMeal = data.meals.values.flatMap { $0 }.map(\.time).max()
        var stats: [String: Any] = [
            "dayCount": days.count,
            "mealCount": mealCount,
            "weightCount": data.weightLogs.count,
            "kgLost": latestW.map { max(0, g.startWeight - $0.value) } ?? 0,
        ]
        stats["latestWeight"] = latestW?.value
        stats["latestWeightDate"] = latestW?.date
        stats["latestWaist"] = latestWaist?.value
        stats["firstDay"] = days.keys.min()
        stats["lastDay"] = days.keys.max()
        stats["lastMealAt"] = lastMeal.map { Timestamp(date: $0) }
        stats["updatedAt"] = Timestamp(date: data.updatedAt)

        return ["profile": profile, "goals": goals, "program": program, "stats": stats.compactMapValues { $0 }]
    }

    // MARK: Rows

    static func dayRows(_ d: AppData) -> [String: [String: Any]] {
        var dates = Set<String>()
        dates.formUnion(d.weightLogs.map(\.date)); dates.formUnion(d.waistLogs.map(\.date))
        dates.formUnion(d.recovery.keys); dates.formUnion(d.health.keys); dates.formUnion(d.water.keys)
        dates.formUnion(d.habits.keys); dates.formUnion(d.supplements.keys); dates.formUnion(d.breathing.keys)
        dates.formUnion(d.meals.keys)
        dates.formUnion(d.exerciseDone.keys.compactMap { $0.count >= 10 ? String($0.prefix(10)) : nil })
        for logs in d.overload.values { dates.formUnion(logs.map(\.date)) }

        let weight = Dictionary(d.weightLogs.map { ($0.date, $0.value) }, uniquingKeysWith: { $1 })
        let waist = Dictionary(d.waistLogs.map { ($0.date, $0.value) }, uniquingKeysWith: { $1 })

        var out: [String: [String: Any]] = [:]
        for date in dates where DateKey.date(date) != nil {
            var r: [String: Any] = ["date": date]
            r["weightKg"] = weight[date]
            r["waistCm"] = waist[date]
            if let rec = d.recovery[date] {
                r["hrv"] = rec.hrv; r["rhr"] = rec.rhr; r["sleepH"] = rec.sleepH; r["deepH"] = rec.deepH
                r["remH"] = rec.remH; r["resp"] = rec.resp; r["mood"] = rec.mood
                r["readiness"] = Store.readiness(rec)
            }
            if let h = d.health[date] {
                if h.steps > 0 { r["steps"] = h.steps }
                r["restingHR"] = h.restingHR; r["activeKcal"] = h.activeKcal; r["basalKcal"] = h.basalKcal
                r["burnedKcal"] = h.burnedKcal
            }
            if let w = d.water[date], w > 0 { r["waterMl"] = w }
            if let s = d.habits[date], !s.isEmpty { r["habits"] = s.sorted(); r["habitCount"] = s.count }
            if let s = d.supplements[date], !s.isEmpty { r["supplements"] = s.sorted(); r["supplementCount"] = s.count }
            if let s = d.breathing[date], !s.isEmpty { r["breathing"] = s.sorted(); r["breathingCount"] = s.count }
            if let meals = d.meals[date], !meals.isEmpty {
                let t = meals.reduce(into: (0.0, 0.0, 0.0, 0.0)) { $0.0 += $1.kcal; $0.1 += $1.protein; $0.2 += $1.carbs; $0.3 += $1.fat }
                r["mealCount"] = meals.count
                r["kcal"] = t.0.rounded(); r["protein"] = t.1.rounded(); r["carbs"] = t.2.rounded(); r["fat"] = t.3.rounded()
                if let burned = d.health[date]?.burnedKcal { r["deficit"] = (burned - t.0).rounded() }
            }
            var lifts: [String: [String: Any]] = [:]
            for (exercise, logs) in d.overload {
                if let l = logs.first(where: { $0.date == date }) {
                    lifts[exercise] = ["kg": l.kg, "reps": l.reps, "volume": l.kg * Double(l.reps)]
                }
            }
            if !lifts.isEmpty { r["lifts"] = lifts }
            let done = d.exerciseDone.filter { $0.key.hasPrefix(date) }.values.reduce(0) { $0 + $1.count }
            if done > 0 { r["exercisesDone"] = done }
            out[date] = r
        }
        return out
    }

    static func mealRows(_ d: AppData) -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        for (date, meals) in d.meals {
            for m in meals {
                var r: [String: Any] = [
                    "date": date, "at": Timestamp(date: m.time), "name": m.name,
                    "kcal": m.kcal, "protein": m.protein, "carbs": m.carbs, "fat": m.fat,
                    "items": m.items.map { ["name": $0.name, "portion": $0.portion, "grams": $0.grams, "kcal": $0.kcal,
                                            "protein": $0.protein, "carbs": $0.carbs, "fat": $0.fat] as [String: Any] },
                ]
                r["slot"] = m.slot; r["confidence"] = m.confidence; r["notes"] = m.notes
                out[m.id] = r
            }
        }
        return out
    }

    // MARK: Change detection

    private static func hash(_ row: [String: Any]) -> String {
        let plain = row.mapValues { v -> Any in (v as? Timestamp).map { $0.seconds } ?? v }
        let data = (try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func cacheKey(_ uid: String) -> String { "mirror-v\(Self.schema)-\(uid)" }

    private func loadCache(_ uid: String) {
        guard hashesUID != uid else { return }
        hashesUID = uid
        hashes = UserDefaults.standard.dictionary(forKey: cacheKey(uid)) as? [String: String] ?? [:]
    }

    private func saveCache(_ uid: String) {
        UserDefaults.standard.set(hashes, forKey: cacheKey(uid))
    }
}
