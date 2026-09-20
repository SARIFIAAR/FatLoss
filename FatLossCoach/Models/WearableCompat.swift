import Foundation

/// The wearables HUMANS works with today — all via Apple Health. `full` = also delivers HRV, so
/// Recovery & Stress run at full accuracy; the rest get an estimated score from HR + sleep.
/// Reference study: docs/wearables/HUMANS_Wearable_Compatibility.md
enum WearableCompat {
    struct Device { let name: String; let note: String; let full: Bool }

    static let devices: [Device] = [
        Device(name: "Apple Watch",  note: "Everything, incl. HRV, ECG, VO₂ max & HR zones", full: true),
        Device(name: "Ultrahuman Ring", note: "HRV, temperature & CGM glucose", full: true),
        Device(name: "Oura Ring",    note: "Sleep stages, HR, temperature, workouts", full: false),
        Device(name: "Garmin",       note: "Sleep, HR, SpO₂, VO₂ max, workouts", full: false),
        Device(name: "Withings",     note: "Sleep, blood pressure, body composition, VO₂ max", full: false),
        Device(name: "Fitbit",       note: "Sleep, HR, SpO₂, steps (via Google Health)", full: false),
        Device(name: "Amazfit / Zepp", note: "Steps, HR, sleep, SpO₂, workouts", full: false),
        Device(name: "RingConn",     note: "Steps, sleep, resting HR, SpO₂", full: false),
    ]
}
