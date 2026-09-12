import Foundation
import HealthKit
import Observation

/// Reads steps, resting HR, HRV, respiratory rate and sleep stages straight from Apple Health —
/// this replaces the web app's manual "Apple Watch sync" form and the Shortcuts URL hack.
@Observable
final class HealthKitManager {
    private let hk = HKHealthStore()

    var isSyncing = false
    var lastError: String?
    var lastSync: Date? = UserDefaults.standard.object(forKey: "hk-last-sync") as? Date {
        didSet { UserDefaults.standard.set(lastSync, forKey: "hk-last-sync") }
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var hasConnected: Bool { lastSync != nil }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
                                               .activeEnergyBurned, .basalEnergyBurned,
                                               .oxygenSaturation, .appleSleepingWristTemperature, .heartRate]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        set.insert(HKObjectType.workoutType())
        return set
    }

    func connectAndSync(store: Store, days: Int = 30) async {
        guard isAvailable else {
            lastError = "Health data isn't available on this device."
            return
        }
        do {
            try await hk.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes)
        } catch {
            lastError = error.localizedDescription
            return
        }
        await sync(store: store, days: days)
    }

    func sync(store: Store, days: Int = 30) async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            // No-op when everything is already decided; shows the sheet only for types added in an update
            // (e.g. active/basal energy, added in 1.0.1) so existing users get the new data too.
            try? await hk.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes)
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            let steps = try await dailyStats(.stepCount, .cumulativeSum, unit: .count(), days: days)
            let active = try await dailyStats(.activeEnergyBurned, .cumulativeSum, unit: .kilocalorie(), days: days)
            let basal  = try await dailyStats(.basalEnergyBurned, .cumulativeSum, unit: .kilocalorie(), days: days)
            let rhr   = try await dailyStats(.restingHeartRate, .discreteAverage, unit: perMinute, days: days)
            let hrv   = try await dailyStats(.heartRateVariabilitySDNN, .discreteAverage, unit: .secondUnit(with: .milli), days: days)
            let resp  = try await dailyStats(.respiratoryRate, .discreteAverage, unit: perMinute, days: days)
            let sleep = try await sleepByNight(days: days)

            for (d, v) in steps { store.setHealth(steps: Int(v.rounded()), on: DateKey.key(d)) }
            for (d, v) in active where v > 0 { store.setHealth(activeKcal: v.rounded(), on: DateKey.key(d)) }
            for (d, v) in basal  where v > 0 { store.setHealth(basalKcal: v.rounded(), on: DateKey.key(d)) }
            for (d, v) in rhr {
                let k = DateKey.key(d)
                store.setHealth(restingHR: v, on: k)
                store.updateRecovery(on: k) { $0.rhr = v }
            }
            for (d, v) in hrv  { store.updateRecovery(on: DateKey.key(d)) { $0.hrv = v } }
            for (d, v) in resp { store.updateRecovery(on: DateKey.key(d)) { $0.resp = v } }
            let spo2 = try await dailyStats(.oxygenSaturation, .discreteAverage, unit: .percent(), days: days)
            let temp = try await dailyStats(.appleSleepingWristTemperature, .discreteAverage,
                                            unit: .degreeCelsius(), days: days)
            for (d, v) in spo2 where v > 0 { store.updateRecovery(on: DateKey.key(d)) { $0.spo2 = v * 100 } }
            for (d, v) in temp where v > 0 { store.updateRecovery(on: DateKey.key(d)) { $0.tempC = v } }
            for (d, n) in sleep where n.total > 0.25 {
                store.updateRecovery(on: DateKey.key(d)) {
                    $0.sleepH = n.total
                    $0.deepH = n.deep > 0 ? n.deep : $0.deepH
                    $0.remH = n.rem > 0 ? n.rem : $0.remH
                    $0.inBedH = n.inBed > n.total ? n.inBed : $0.inBedH
                    $0.bedTime = n.bedTime ?? $0.bedTime
                    $0.wakeTime = n.wakeTime ?? $0.wakeTime
                    $0.awakeCount = n.awakeCount > 0 ? n.awakeCount : $0.awakeCount
                }
            }
            let workouts = try await workoutsByDay(days: days)
            for (key, list) in workouts { store.setWorkouts(list, on: key) }
            lastSync = Date()
            let todaySteps = steps.first { DateKey.key($0.key) == store.today }?.value ?? 0
            let todayBurn = store.healthToday?.burnedKcal
            store.showToast("Apple Health synced · \(Int(todaySteps).formatted()) steps"
                            + (todayBurn.map { " · \(Int($0)) kcal burned" } ?? "") + " 🍎")
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Queries

    private func dailyStats(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions,
                            unit: HKUnit, days: Int) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let anchor = cal.startOfDay(for: end)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let isSum = option == .cumulativeSum

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: option,
                                                anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, collection, error in
                if let error { cont.resume(throwing: error); return }
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let qty = isSum ? stats.sumQuantity() : stats.averageQuantity()
                    if let qty { out[stats.startDate] = qty.doubleValue(for: unit) }
                }
                cont.resume(returning: out)
            }
            hk.execute(q)
        }
    }

    struct SleepNight {
        var total = 0.0; var deep = 0.0; var rem = 0.0
        var inBed = 0.0                 // explicit inBed samples, else span first-asleep → last-wake
        var bedTime: Date?; var wakeTime: Date?
        var awakeCount = 0
    }

    /// Sleep hours bucketed by the morning the sleep ended.
    private func sleepByNight(days: Int) async throws -> [Date: SleepNight] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            hk.execute(q)
        }

        // Prefer the source with the richest data (usually the Watch) to avoid double counting phone + watch.
        let bySource = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        let best = bySource.max { a, b in
            let aStaged = a.value.contains { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            let bStaged = b.value.contains { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            if aStaged != bStaged { return bStaged }
            return a.value.count < b.value.count
        }?.value ?? samples

        var out: [Date: SleepNight] = [:]
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        var inBedSpans: [Date: (Double, Date?, Date?)] = [:]   // explicit inBed: hours, first, last
        for s in best {
            let night = cal.startOfDay(for: s.endDate)
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600
            var n = out[night] ?? SleepNight()
            if s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                var span = inBedSpans[night] ?? (0, nil, nil)
                span.0 += h
                span.1 = min(span.1 ?? s.startDate, s.startDate)
                span.2 = max(span.2 ?? s.endDate, s.endDate)
                inBedSpans[night] = span
            } else if s.value == HKCategoryValueSleepAnalysis.awake.rawValue {
                n.awakeCount += 1
            } else if asleep.contains(s.value) {
                n.total += h
                if s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue { n.deep += h }
                if s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue { n.rem += h }
                n.bedTime = min(n.bedTime ?? s.startDate, s.startDate)
                n.wakeTime = max(n.wakeTime ?? s.endDate, s.endDate)
            }
            out[night] = n
        }
        // In-bed time: explicit samples when present, else the asleep span (includes awake gaps).
        for (night, n) in out {
            var m = n
            if let span = inBedSpans[night], span.0 > n.total {
                m.inBed = span.0
                m.bedTime = span.1 ?? m.bedTime
            } else if let b = n.bedTime, let w = n.wakeTime {
                m.inBed = w.timeIntervalSince(b) / 3600
            }
            out[night] = m
        }
        return out
    }

    // MARK: Workouts

    /// Workouts with per-zone HR minutes. Zones are % of the max HR observed across recent
    /// workouts (floor 180): z1 <60, z2 60-70, z3 70-80, z4 80-90, z5 90+.
    private func workoutsByDay(days: Int) async throws -> [String: [WorkoutEntry]] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            hk.execute(q)
        }
        guard !workouts.isEmpty else { return [:] }

        var perWorkoutHR: [UUID: [(Date, Double)]] = [:]
        for w in workouts {
            perWorkoutHR[w.uuid] = try await heartRateSamples(from: w.startDate, to: w.endDate)
        }
        let observedMax = perWorkoutHR.values.flatMap { $0.map(\.1) }.max() ?? 0
        let maxHR = max(180, observedMax)

        var out: [String: [WorkoutEntry]] = [:]
        for w in workouts {
            let hr = perWorkoutHR[w.uuid] ?? []
            var zones = [0.0, 0, 0, 0, 0]
            for (i, s) in hr.enumerated() {
                // A sample covers the gap to the next one (capped — gaps mean the strap was off).
                let next = i + 1 < hr.count ? hr[i + 1].0 : w.endDate
                let mins = min(next.timeIntervalSince(s.0), 60) / 60
                let pct = s.1 / maxHR
                let z = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4
                zones[z] += mins
            }
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let hrValues = hr.map(\.1)
            let key = DateKey.key(w.startDate)
            let entry = WorkoutEntry(id: w.uuid.uuidString, date: key,
                                     name: w.workoutActivityType.displayName, start: w.startDate,
                                     minutes: w.duration / 60, kcal: kcal,
                                     avgHR: hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count),
                                     maxHR: hrValues.max(),
                                     zoneMin: hrValues.isEmpty ? [] : zones)
            out[key, default: []].append(entry)
        }
        return out
    }

    private func heartRateSamples(from: Date, to: Date) async throws -> [(Date, Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                let samples = (results as? [HKQuantitySample]) ?? []
                cont.resume(returning: samples.map { ($0.startDate, $0.quantity.doubleValue(for: perMinute)) })
            }
            hk.execute(q)
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycle"
        case .swimming: "Swim"
        case .highIntensityIntervalTraining: "HIIT"
        case .rowing: "Row"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stairs"
        case .yoga: "Yoga"
        case .coreTraining: "Core"
        case .soccer: "Football"
        case .hiking: "Hike"
        default: "Workout"
        }
    }
}
