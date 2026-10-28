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

    /// Gate for the automatic foreground sync. The old `hasConnected` gate keyed off a successful
    /// LAST SYNC — one mid-sync HealthKit error meant `lastSync` never stamped and auto-sync silently
    /// died forever (the 2026-10-27 empty-Watch-dashboard bug). Instead ask HealthKit whether the user
    /// has already been through the permission sheet; if so, syncing is sanctioned.
    func shouldAutoSync() async -> Bool {
        if hasConnected { return true }
        guard isAvailable else { return false }
        // Probe only the v1 CORE types (asked since the first build). The full `readTypes` set gains
        // types across updates, which flips the status back to .shouldRequest and would wrongly read
        // as "never connected". A user who answered the core sheet opted in; the sync's own
        // requestAuthorization then shows the sheet once for any newly-added types.
        var core = Set<HKObjectType>()
        for id in [HKQuantityTypeIdentifier.stepCount, .restingHeartRate, .heartRateVariabilitySDNN] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { core.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { core.insert(sleep) }
        let status = try? await hk.statusForAuthorizationRequest(toShare: Set<HKSampleType>(), read: core)
        return status == .unnecessary
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
                                               .activeEnergyBurned, .basalEnergyBurned,
                                               .oxygenSaturation, .appleSleepingWristTemperature, .heartRate,
                                               .bodyFatPercentage, .leanBodyMass, .bodyMass, .vo2Max,
                                               // Metabolic & cardiovascular extras (glucose, BP, hydration)
                                               .bloodGlucose, .bloodPressureSystolic, .bloodPressureDiastolic,
                                               .dietaryWater, .heartRateRecoveryOneMinute]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        if let mind = HKObjectType.categoryType(forIdentifier: .mindfulSession) { set.insert(mind) }
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

    /// Write a nap to Apple Health (asleep block ending now) so it flows back into the app's sleep data.
    func logNap(minutes: Int, store: Store) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        do { try await hk.requestAuthorization(toShare: [type], read: readTypes) }
        catch { lastError = error.localizedDescription; return }
        let end = Date()
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        let sample = HKCategorySample(type: type,
                                      value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      start: start, end: end)
        do {
            try await hk.save(sample)
            await sync(store: store)
            store.showToast("Nap logged · \(minutes) min")
        } catch {
            lastError = "Couldn't save the nap: \(error.localizedDescription)"
        }
    }

    func sync(store: Store, days: Int = 30) async {
        // VB9 band-only mode: ignore Apple Health entirely so the dashboard reflects only the HUMANS band.
        if UserDefaults.standard.bool(forKey: "vb9Exclusive") { return }
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
            // No-op when everything is already decided; shows the sheet only for types added in an update
            // (e.g. active/basal energy, added in 1.0.1) so existing users get the new data too.
            try? await hk.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes)
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            // Each metric fails alone (logged) — one HealthKit error must never abort the whole sync.
            func safe(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions,
                      unit: HKUnit, watchOnly: Bool = false) async -> [Date: Double] {
                do { return try await dailyStats(id, option, unit: unit, days: days, watchOnly: watchOnly) }
                catch {
                    NSLog("[Health] %@ failed: %@", id.rawValue, error.localizedDescription)
                    lastError = error.localizedDescription
                    return [:]
                }
            }
            let steps = await safe(.stepCount, .cumulativeSum, unit: .count(), watchOnly: true)
            let active = await safe(.activeEnergyBurned, .cumulativeSum, unit: .kilocalorie(), watchOnly: true)
            let basal  = await safe(.basalEnergyBurned, .cumulativeSum, unit: .kilocalorie(), watchOnly: true)
            let rhr   = await safe(.restingHeartRate, .discreteAverage, unit: perMinute, watchOnly: true)
            let hrv   = await safe(.heartRateVariabilitySDNN, .discreteAverage, unit: .secondUnit(with: .milli), watchOnly: true)
            let resp  = await safe(.respiratoryRate, .discreteAverage, unit: perMinute, watchOnly: true)
            let sleep: [Date: SleepNight]
            do { sleep = try await sleepByNight(days: days) }
            catch { NSLog("[Health] sleep failed: %@", error.localizedDescription); lastError = error.localizedDescription; sleep = [:] }

            // Everything below is Watch/Health-measured → the Apple source store only (the strap view stays clean).
            for (d, v) in steps { store.setHealth(steps: Int(v.rounded()), source: .apple, on: DateKey.key(d)) }
            for (d, v) in active where v > 0 { store.setHealth(activeKcal: v.rounded(), source: .apple, on: DateKey.key(d)) }
            for (d, v) in basal  where v > 0 { store.setHealth(basalKcal: v.rounded(), source: .apple, on: DateKey.key(d)) }
            for (d, v) in rhr {
                let k = DateKey.key(d)
                store.setHealth(restingHR: v, source: .apple, on: k)
                store.updateRecovery(on: k, source: .apple) { $0.rhr = v }
            }
            for (d, v) in hrv  { store.updateRecovery(on: DateKey.key(d), source: .apple) { $0.hrv = v } }
            for (d, v) in resp { store.updateRecovery(on: DateKey.key(d), source: .apple) { $0.resp = v } }
            let spo2 = await safe(.oxygenSaturation, .discreteAverage, unit: .percent(), watchOnly: true)
            let temp = await safe(.appleSleepingWristTemperature, .discreteAverage, unit: .degreeCelsius(), watchOnly: true)
            for (d, v) in spo2 where v > 0 { store.updateRecovery(on: DateKey.key(d), source: .apple) { $0.spo2 = v * 100 } }
            for (d, v) in temp where v > 0 { store.updateRecovery(on: DateKey.key(d), source: .apple) { $0.tempC = v } }
            for (d, n) in sleep where n.total > 0.25 {
                store.updateRecovery(on: DateKey.key(d), source: .apple) {
                    $0.sleepH = n.total
                    $0.deepH = n.deep > 0 ? n.deep : $0.deepH
                    $0.remH = n.rem > 0 ? n.rem : $0.remH
                    $0.inBedH = n.inBed > n.total ? n.inBed : $0.inBedH
                    $0.bedTime = n.bedTime ?? $0.bedTime
                    $0.wakeTime = n.wakeTime ?? $0.wakeTime
                    $0.awakeCount = n.awakeCount > 0 ? n.awakeCount : $0.awakeCount
                    $0.napH = n.nap > 0 ? n.nap : $0.napH
                }
            }
            let workouts = (try? await workoutsByDay(days: days)) ?? [:]
            for (key, list) in workouts { store.setWorkouts(list, source: .apple, on: key) }
            // Body composition — written to Apple Health by any BIA scale (Hume, Withings, etc.).
            let bodyFat = await safe(.bodyFatPercentage, .discreteAverage, unit: .percent())
            let lean    = await safe(.leanBodyMass, .discreteAverage, unit: .gramUnit(with: .kilo))
            for (d, v) in bodyFat where v > 0 { store.setHealth(bodyFatPct: v * 100, source: .apple, on: DateKey.key(d)) }
            for (d, v) in lean where v > 0 { store.setHealth(leanMassKg: v, source: .apple, on: DateKey.key(d)) }
            let mlKgMin = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
            let vo2 = await safe(.vo2Max, .discreteAverage, unit: mlKgMin, watchOnly: true)
            for (d, v) in vo2 where v > 0 { store.setHealth(vo2Max: v, source: .apple, on: DateKey.key(d)) }
            // Metabolic & cardiovascular extras.
            let mgPerDL = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            let glucose = await safe(.bloodGlucose, .discreteAverage, unit: mgPerDL)
            let sys = await safe(.bloodPressureSystolic, .discreteAverage, unit: .millimeterOfMercury())
            let dia = await safe(.bloodPressureDiastolic, .discreteAverage, unit: .millimeterOfMercury())
            let water = await safe(.dietaryWater, .cumulativeSum, unit: .literUnit(with: .milli))
            for (d, v) in glucose where v > 0 { store.setHealth(glucoseMgDl: v, source: .apple, on: DateKey.key(d)) }
            for (d, v) in sys where v > 0 { store.setHealth(bpSystolic: v, source: .apple, on: DateKey.key(d)) }
            for (d, v) in dia where v > 0 { store.setHealth(bpDiastolic: v, source: .apple, on: DateKey.key(d)) }
            for (d, v) in water where v > 0 { store.setHydrationFromHealth(Int(v.rounded()), on: DateKey.key(d)) }
            // Heart-rate recovery: 1-minute HR drop after a workout — higher = fitter.
            let hrr = await safe(.heartRateRecoveryOneMinute, .discreteMax, unit: perMinute, watchOnly: true)
            for (d, v) in hrr where v > 0 { store.setHealth(hrrBpm: v, source: .apple, on: DateKey.key(d)) }
            // All-day HR envelope + zone minutes from the Watch's raw heart-rate samples. The Watch records
            // HR all day (sparse at rest, dense in workouts), so the Apple view gets the same all-day
            // HR-range row and zone card as the strap — same bucketing (≥50% of max HR counts toward a zone).
            let hrSamples = (try? await allHeartRateSamples(days: min(days, 30))) ?? []
            if !hrSamples.isEmpty {
                let maxHR = Double(store.data.reminders.maxHrOverride ?? (220 - (store.data.intake?.age ?? 30)))
                for (key, daySamples) in Dictionary(grouping: hrSamples, by: { DateKey.key($0.0) }) {
                    let sorted = daySamples.sorted { $0.0 < $1.0 }
                    var z = [0.0, 0, 0, 0, 0]
                    for (i, s) in sorted.enumerated() {
                        // A sample covers the gap to the next one, capped at 5 min (background cadence).
                        let next = i + 1 < sorted.count ? sorted[i + 1].0 : s.0
                        let mins = min(next.timeIntervalSince(s.0), 300) / 60
                        let pct = s.1 / maxHR
                        let zi = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4
                        if pct >= 0.5 { z[zi] += mins }
                    }
                    store.mutateHealth(.apple, on: key) { h in
                        h.hrMinDay = sorted.map(\.1).min()
                        h.hrMaxDay = sorted.map(\.1).max()
                        if z.contains(where: { $0 > 0 }) { h.hrZoneMin = z }
                    }
                }
            }
            lastSync = Date()
            NSLog("[Health] sync done · steps=%d active=%d rhr=%d hrv=%d resp=%d sleep=%d workouts=%d allHR=%d samples",
                  steps.count, active.count, rhr.count, hrv.count, resp.count, sleep.count, workouts.count, hrSamples.count)
            let todaySteps = steps.first { DateKey.key($0.key) == store.today }?.value ?? 0
            let todayBurn = store.healthToday?.burnedKcal
            store.showToast("Apple Health synced · \(Int(todaySteps).formatted()) steps"
                            + (todayBurn.map { " · \(Int($0)) kcal burned" } ?? "") + " 🍎")
    }

    // MARK: Queries

    /// Matches samples recorded by an Apple Watch (HKDevice model "Watch"). The "Apple Watch" body
    /// source must really be the Watch — not iPhone step counts or other apps writing to Apple Health.
    private static let watchDevice = HKQuery.predicateForObjects(
        withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"])

    /// `watchOnly` restricts a wearable metric to Watch-recorded samples. Fallback: when the filtered
    /// window has NO Watch samples at all (no Watch paired, or a derived type the system doesn't
    /// device-stamp), the unfiltered Apple Health value is used so the view doesn't go dark.
    private func dailyStats(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions,
                            unit: HKUnit, days: Int, watchOnly: Bool = false) async throws -> [Date: Double] {
        if watchOnly {
            let filtered = try await dailyStatsRun(id, option, unit: unit, days: days, device: Self.watchDevice)
            if !filtered.isEmpty { return filtered }
        }
        return try await dailyStatsRun(id, option, unit: unit, days: days, device: nil)
    }

    private func dailyStatsRun(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions,
                               unit: HKUnit, days: Int, device: NSPredicate?) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let anchor = cal.startOfDay(for: end)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) ?? anchor
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = device.map { NSCompoundPredicate(andPredicateWithSubpredicates: [dates, $0]) } ?? dates
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
        var nap = 0.0                   // total daytime nap hours (separate from the main sleep)
        var napCount = 0
    }

    /// A contiguous asleep block (segments within 60 min are one session).
    private struct SleepSession {
        var start: Date; var end: Date; var deep = 0.0; var rem = 0.0
        var hours: Double { end.timeIntervalSince(start) / 3600 }
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

        // Watch-recorded sleep only (fallback: all sources when no Watch samples exist at all).
        let watchSamples = samples.filter { $0.device?.model == "Watch" }
        let pool = watchSamples.isEmpty ? samples : watchSamples

        // Prefer the source with the richest data (usually the Watch) to avoid double counting phone + watch.
        let bySource = Dictionary(grouping: pool) { $0.sourceRevision.source.bundleIdentifier }
        let best = bySource.max { a, b in
            let aStaged = a.value.contains { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            let bStaged = b.value.contains { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            if aStaged != bStaged { return bStaged }
            return a.value.count < b.value.count
        }?.value ?? pool

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        // Cluster asleep samples into sessions (segments within 60 min = one session).
        let asleepSamples = best.filter { asleep.contains($0.value) }.sorted { $0.startDate < $1.startDate }
        var sessions: [SleepSession] = []
        for s in asleepSamples {
            let isDeep = s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            let isREM = s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            let dur = s.endDate.timeIntervalSince(s.startDate) / 3600
            if var last = sessions.last, s.startDate.timeIntervalSince(last.end) < 3600 {
                last.end = max(last.end, s.endDate)
                last.deep += isDeep ? dur : 0
                last.rem += isREM ? dur : 0
                sessions[sessions.count - 1] = last
            } else {
                sessions.append(SleepSession(start: s.startDate, end: s.endDate,
                                             deep: isDeep ? dur : 0, rem: isREM ? dur : 0))
            }
        }

        // Group sessions by the day they ended; the longest is the main sleep, the rest are naps.
        var out: [Date: SleepNight] = [:]
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.end) }
        for (day, daySessions) in byDay {
            let sorted = daySessions.sorted { $0.hours > $1.hours }
            guard let main = sorted.first else { continue }
            var n = SleepNight()
            n.total = main.hours; n.deep = main.deep; n.rem = main.rem
            n.bedTime = main.start; n.wakeTime = main.end
            for nap in sorted.dropFirst() where nap.hours >= 0.25 && nap.hours <= 3 {
                n.nap += nap.hours; n.napCount += 1
            }
            out[day] = n
        }

        // Awake segments (disturbances) and explicit inBed spans, bucketed to the ending day.
        var inBedSpans: [Date: (Double, Date?, Date?)] = [:]
        for s in best {
            let night = cal.startOfDay(for: s.endDate)
            guard out[night] != nil else { continue }
            if s.value == HKCategoryValueSleepAnalysis.awake.rawValue {
                out[night]?.awakeCount += 1
            } else if s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                var span = inBedSpans[night] ?? (0, nil, nil)
                span.0 += s.endDate.timeIntervalSince(s.startDate) / 3600
                span.1 = min(span.1 ?? s.startDate, s.startDate)
                span.2 = max(span.2 ?? s.endDate, s.endDate)
                inBedSpans[night] = span
            }
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

    /// Every Watch-recorded heart-rate sample in the window (for the all-day envelope + zone minutes).
    private func allHeartRateSamples(days: Int) async throws -> [(Date, Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: end)) ?? end
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [dates, Self.watchDevice])
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                let out = ((results as? [HKQuantitySample]) ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: perMinute)) }
                cont.resume(returning: out)
            }
            hk.execute(q)
        }
    }

    // MARK: Workouts

    /// Workouts with per-zone HR minutes. Zones are % of the max HR observed across recent
    /// workouts (floor 180): z1 <60, z2 60-70, z3 70-80, z4 80-90, z5 90+.
    private func workoutsByDay(days: Int) async throws -> [String: [WorkoutEntry]] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let allWorkouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            hk.execute(q)
        }
        // Watch-recorded workouts only (fallback: all sources when the Watch recorded none).
        let watchWorkouts = allWorkouts.filter { $0.device?.model == "Watch" }
        let workouts = watchWorkouts.isEmpty ? allWorkouts : watchWorkouts
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
