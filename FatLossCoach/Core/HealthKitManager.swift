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
                                               .activeEnergyBurned, .basalEnergyBurned]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
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
            for (d, n) in sleep where n.total > 0.25 {
                store.updateRecovery(on: DateKey.key(d)) {
                    $0.sleepH = n.total
                    $0.deepH = n.deep > 0 ? n.deep : $0.deepH
                    $0.remH = n.rem > 0 ? n.rem : $0.remH
                }
            }
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

    struct SleepNight { var total = 0.0; var deep = 0.0; var rem = 0.0 }

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
        for s in best where asleep.contains(s.value) {
            let night = cal.startOfDay(for: s.endDate)
            var n = out[night] ?? SleepNight()
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600
            n.total += h
            if s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue { n.deep += h }
            if s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue { n.rem += h }
            out[night] = n
        }
        return out
    }
}
