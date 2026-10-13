import Foundation

// Ingestion of VB9 band data into the Store. Mirrors `applyWearable` (Whoop/Oura): band values fill in
// only the fields they provide, then flow through the same BodyMetrics engine as Apple Health. Device-only
// extras (ECG, continuous-HR envelope, measured stress/fatigue) land in the new AppData slots.
extension Store {

    /// Bulk history sync (sleep / HR / SpO₂ / temperature / steps / BP / stress), one record per day.
    func applyVB9History(days: [VB9Day], workouts: [VB9Work]) {
        for d in days {
            updateRecovery(on: d.date) { r in
                if let v = d.hrv, v > 0 { r.hrv = v }
                if let v = d.rhr, v > 0 { r.rhr = v }
                if let v = d.sleepH, v > 0 { r.sleepH = v }
                if let v = d.deepH, v > 0 { r.deepH = v }
                if let v = d.remH, v > 0 { r.remH = v }
                if let v = d.resp, v > 0 { r.resp = v }
                if let v = d.spo2, v > 0 { r.spo2 = v }
                if let v = d.tempC, v > 0 { r.tempC = v }
                if let v = d.stress, v > 0 { r.stressMeasured = v }
                if let v = d.fatigue, v > 0 { r.fatigue = v }
            }
            setHealth(steps: d.steps, activeKcal: d.activeKcal,
                      bpSystolic: d.bpSystolic, bpDiastolic: d.bpDiastolic, on: d.date)
            if d.hrMinDay != nil || d.hrMaxDay != nil {
                var h = data.health[d.date] ?? HealthDay()
                if let v = d.hrMinDay { h.hrMinDay = v }
                if let v = d.hrMaxDay { h.hrMaxDay = v }
                data.health[d.date] = h
            }
        }
        for w in workouts {
            let id = "vb9-\(w.date)-\(Int((w.minutes ?? 0).rounded()))-\(w.name ?? "")"
            var list = data.workouts[w.date] ?? []
            guard !list.contains(where: { $0.id == id }) else { continue }
            list.append(WorkoutEntry(id: id, date: w.date, name: w.name ?? "Workout",
                                     start: DateKey.date(w.date) ?? Date(),
                                     minutes: w.minutes ?? 0, kcal: w.kcal, avgHR: w.avgHR))
            data.workouts[w.date] = list
        }
    }

    /// One-key health measurement → today's recovery (stress/fatigue/spo₂/resp) + health (BP).
    func applyVB9OneKey(_ r: VB9OneKey, on day: String? = nil) {
        let k = day ?? today
        updateRecovery(on: k) { rec in
            if let v = r.stress { rec.stressMeasured = Double(v) }
            if let v = r.fatigue { rec.fatigue = Double(v) }
            if let v = r.spo2, v > 0 { rec.spo2 = Double(v) }
            if let v = r.breathRate, v > 0 { rec.resp = Double(v) }
            if let v = r.temperatureC, v > 0 { rec.tempC = v }
        }
        setHealth(restingHR: r.hr.map(Double.init),
                  bpSystolic: r.sbp.map(Double.init), bpDiastolic: r.dbp.map(Double.init), on: k)
    }

    /// Persist an ECG recording + its AI analysis (deduped by id per day).
    func recordECG(_ result: ECGResult) {
        var list = data.ecg[result.date] ?? []
        if let i = list.firstIndex(where: { $0.id == result.id }) { list[i] = result }
        else { list.append(result) }
        data.ecg[result.date] = list.sorted { $0.at < $1.at }
        // Mirror the ECG-AI stress/fatigue into the day's recovery so the Body dashboard corroborates.
        updateRecovery(on: result.date) { rec in
            if let v = result.stress, v > 0, rec.stressMeasured == nil { rec.stressMeasured = v }
            if let v = result.fatigue, v > 0, rec.fatigue == nil { rec.fatigue = v }
        }
    }

    /// Most recent ECG recording across all days (for the Body "Heart Rhythm" card).
    var latestECG: ECGResult? {
        data.ecg.values.flatMap { $0 }.max { $0.at < $1.at }
    }

    func setBand(_ info: BandInfo) { data.band = info }
}
