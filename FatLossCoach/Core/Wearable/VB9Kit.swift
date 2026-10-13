import Foundation

// VB9 wristband (IWOWN / Zeroner "Mid-Autumn" protobuf BLE SDK) — typed results + ingestion into the Store.
//
// Transport (BLE) lives in VB9Manager.swift. This file is pure Swift with NO dependency on the vendor
// framework, so it compiles and is unit-testable on the simulator today. The manager hands these value
// types to the Store's `applyVB9…` methods, which merge into the SAME AppData the Apple-Health and
// Whoop/Oura paths feed — so BodyMetrics (Recovery / Strain / Stress / Physical Age) is unchanged.
//
// WELLNESS framing: rhythm / AF / heart-age / QTc are informational, never a diagnosis (see ECGResult).

// MARK: - Normalised payloads the manager produces

/// One day of band-sourced vitals (history sync). Mirrors WearableLink.Sync.Day + band-only extras.
struct VB9Day {
    var date: String                 // DateKey
    var hrv: Double?                 // SDNN ms
    var rhr: Double?                 // resting HR bpm
    var sleepH: Double?
    var deepH: Double?
    var remH: Double?
    var resp: Double?                // breaths/min
    var spo2: Double?                // %
    var tempC: Double?               // skin temperature °C
    var steps: Int?
    var activeKcal: Double?
    var hrMinDay: Double?            // continuous-HR envelope (band auto-HR)
    var hrMaxDay: Double?
    var bpSystolic: Double?
    var bpDiastolic: Double?
    var stress: Double?              // one-key stress index 0–100
    var fatigue: Double?             // one-key fatigue index 0–100
}

/// A workout/sport session pulled from the band.
struct VB9Work {
    var date: String
    var name: String?
    var minutes: Double?
    var kcal: Double?
    var avgHR: Double?
}

/// The "one-key health measurement" bundle (device measures ~60 s, returns one result).
struct VB9OneKey {
    var fatigue: Int?
    var stress: Int?
    var spo2: Int?
    var hr: Int?
    var sbp: Int?                    // systolic
    var dbp: Int?                    // diastolic
    var breathRate: Int?
    var temperatureC: Double?        // already °C (SDK sends ×10 — the manager divides)
}

// MARK: - SDK JSON mirrors (decoded from the strings calculateEcgAiJson / calculateAFByRRIForJson return)

/// Lenient mirror of the ECG-AI JSON (see docs AI心电分析json字段说明). Every field optional.
struct VB9ECGAnalysis: Decodable {
    struct AIResult: Decodable { var type: Int?; var type_name: String? }
    struct HRV: Decodable { var SDNN: Double?; var rMSSD: Double?; var pNN50: Double?; var HR: Int? }
    struct Grade: Decodable {
        var fatigue: Double?; var pressure: Double?; var score: Int?
        var sympathetic_nerve: Double?; var parasympathetic: Double?; var autonomic_balance: Double?
    }
    struct QRS: Decodable {
        var avgHr: Int?; var avgPrIntervals: Int?; var avgQrs: Int?; var avgQtc: Int?
        var heartAge: Int?; var score: Int?; var scoreDescription: String?; var diagLabels: [String]?
    }
    var AI_Result: AIResult?
    var HRV: HRV?
    var GradeInfo: Grade?
    var QRS: QRS?
    var RRI: [Int]?
}

/// Lenient mirror of the AF-AI JSON (see docs 房颤结果json字段说明).
struct VB9AFAnalysis: Decodable {
    struct Result: Decodable { var level: Double?; var type: Int?; var type_name: String? }
    var AF_Result: Result?
}

enum VB9Parse {
    static func ecg(_ json: String) -> VB9ECGAnalysis? {
        guard let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VB9ECGAnalysis.self, from: d)
    }
    static func af(_ json: String) -> VB9AFAnalysis? {
        guard let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VB9AFAnalysis.self, from: d)
    }

    /// Fold an ECG-AI (and optional AF-AI) analysis into our persisted ECGResult.
    static func result(date: String, at: Date, ecg: VB9ECGAnalysis?, af: VB9AFAnalysis?) -> ECGResult {
        var r = ECGResult(date: date)
        r.at = at
        if let a = ecg?.AI_Result { r.rhythm = a.type_name; r.rhythmCode = a.type }
        if let q = ecg?.QRS {
            r.avgHr = q.avgHr; r.qtcMs = q.avgQtc; r.prMs = q.avgPrIntervals; r.qrsMs = q.avgQrs
            r.heartAge = q.heartAge; r.score = q.score; r.scoreGrade = q.scoreDescription
        }
        if let h = ecg?.HRV { r.sdnn = h.SDNN; r.rmssd = h.rMSSD; r.pnn50 = h.pNN50 }
        if let g = ecg?.GradeInfo {
            r.sympathetic = g.sympathetic_nerve; r.parasympathetic = g.parasympathetic
            r.autonomicBalance = g.autonomic_balance; r.stress = g.pressure; r.fatigue = g.fatigue
        }
        if let af = af?.AF_Result {
            r.afLevel = af.level
            // type 5 = atrial fibrillation (AE/AD_TYPE_SINUS_ATRIAL_FIBRILLATION)
            r.afDetected = af.type == 5
        } else if r.rhythmCode == 5 {
            r.afDetected = true
        }
        return r
    }
}
