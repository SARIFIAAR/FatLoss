import Foundation

struct Habit: Identifiable, Hashable {
    let key: String
    let label: String
    let time: String
    var id: String { key }
}

struct Supplement: Identifiable, Hashable {
    let key: String
    let name: String
    let dose: String
    let when: String
    var id: String { key }
}

struct Exercise: Identifiable, Hashable {
    let name: String
    let sets: String
    let muscles: String
    let images: [URL]
    var id: String { name }

    init(_ name: String, _ sets: String, _ muscles: String, _ slug: String) {
        self.name = name
        self.sets = sets
        self.muscles = muscles
        let base = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
        self.images = ["0", "1"].compactMap { URL(string: base + slug + "/" + $0 + ".jpg") }
    }
}

struct WorkoutDay: Identifiable, Hashable {
    let day: String       // "Mon"
    let label: String
    let tag: String
    let exercises: [Exercise]
    var id: String { day }
    var isTraining: Bool { !exercises.isEmpty }
}

struct BreathingSlot: Identifiable {
    let icon: String
    let time: String
    let name: String
    let detail: String
    var id: String { name }
}

struct Meal: Identifiable {
    let name: String
    let time: String
    let kcal: String
    var id: String { name }
}

/// Static programme content, ported 1:1 from the web app.
enum Plan {
    static let habits: [Habit] = [
        Habit(key: "walk",    label: "Morning Walk 🚶",        time: "30–45 min"),
        Habit(key: "workout", label: "Workout Done 🏋️",       time: "Mon/Wed/Fri"),
        Habit(key: "water",   label: "Water 3L 💧",            time: "all day"),
        Habit(key: "kitchen", label: "Kitchen Closed 9pm 🌙",  time: "9:00 PM"),
        Habit(key: "breath",  label: "Breathing Exercise 🌬️", time: "any time"),
        Habit(key: "sleep",   label: "In Bed by 11pm 😴",      time: "11:00 PM"),
    ]

    static let supplements: [Supplement] = [
        Supplement(key: "vd3", name: "Vitamin D3",              dose: "2000–4000 IU", when: "With breakfast"),
        Supplement(key: "o3",  name: "Omega-3",                 dose: "2–3g EPA+DHA", when: "With meal"),
        Supplement(key: "mg",  name: "Magnesium Glycinate",     dose: "300–400mg",    when: "At night"),
        Supplement(key: "wh",  name: "Whey Protein (optional)", dose: "25–30g",       when: "Post-workout"),
    ]

    /// Supplements shown in the 7-day adherence card.
    static let trackedSupplements = ["vd3", "o3", "mg"]

    static let workouts: [WorkoutDay] = [
        WorkoutDay(day: "Mon", label: "Push Day", tag: "Chest · Shoulders · Triceps", exercises: [
            Exercise("Goblet Squat",        "3×12–15",  "Quads, Glutes",  "Goblet_Squat"),
            Exercise("DB Bench Press",      "3×10–12",  "Chest, Triceps", "Dumbbell_Bench_Press"),
            Exercise("DB Shoulder Press",   "3×10–12",  "Shoulders",      "Dumbbell_Shoulder_Press"),
            Exercise("Leg Press (machine)", "3×12–15",  "Quads, Glutes",  "Leg_Press"),
            Exercise("Tricep Pushdowns",    "3×12–15",  "Triceps",        "Reverse_Grip_Triceps_Pushdown"),
            Exercise("Plank",               "3×30–45s", "Core",           "Plank"),
        ]),
        WorkoutDay(day: "Tue", label: "Rest / Walk", tag: "Active recovery", exercises: []),
        WorkoutDay(day: "Wed", label: "Pull Day", tag: "Back · Biceps", exercises: [
            Exercise("DB Romanian Deadlift", "3×10–12",  "Hamstrings, Glutes",    "Romanian_Deadlift"),
            Exercise("Lat Pulldown",         "3×10–12",  "Lats, Biceps",          "Close-Grip_Front_Lat_Pulldown"),
            Exercise("Seated Cable Row",     "3×10–12",  "Mid Back",              "Elevated_Cable_Rows"),
            Exercise("DB Bicep Curls",       "3×10–12",  "Biceps",                "Dumbbell_Bicep_Curl"),
            Exercise("Face Pulls",           "3×15",     "Rear Delt, Upper Back", "Face_Pull"),
            Exercise("Dead Bug",             "3×10/side", "Core",                 "Dead_Bug"),
        ]),
        WorkoutDay(day: "Thu", label: "Rest / Walk", tag: "Active recovery", exercises: []),
        WorkoutDay(day: "Fri", label: "Legs + Full Body", tag: "Legs · Core", exercises: [
            Exercise("DB Walking Lunges",  "3×12/leg",  "Quads, Glutes",       "Dumbbell_Lunges"),
            Exercise("Hip Thrust",         "3×12–15",   "Glutes, Hamstrings",  "Barbell_Hip_Thrust"),
            Exercise("Leg Curl (machine)", "3×12–15",   "Hamstrings",          "Ball_Leg_Curl"),
            Exercise("Incline DB Press",   "3×10–12",   "Upper Chest",         "Hammer_Grip_Incline_DB_Bench_Press"),
            Exercise("Cable Woodchop",     "3×12/side", "Core, Obliques",      "Standing_Cable_Wood_Chop"),
            Exercise("Calf Raises",        "4×15–20",   "Calves",              "Donkey_Calf_Raises"),
        ]),
        WorkoutDay(day: "Sat", label: "Active Recovery", tag: "Walk 30–45 min", exercises: []),
        WorkoutDay(day: "Sun", label: "Rest", tag: "Full rest day", exercises: []),
    ]

    static func workout(for day: String) -> WorkoutDay? { workouts.first { $0.day == day } }

    /// "Mon" ... "Sun" for today, independent of the device locale.
    static var todayAbbrev: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: Date())
    }

    static let breathing: [BreathingSlot] = [
        BreathingSlot(icon: "🌅", time: "7:00 AM",           name: "Box Breathing",   detail: "Inhale 4s · Hold 4s · Exhale 4s · Hold 4s — 5 min"),
        BreathingSlot(icon: "💪", time: "Pre-Workout",       name: "Belly Breathing", detail: "Deep diaphragm breaths — 3 min to activate focus"),
        BreathingSlot(icon: "🌙", time: "Evening (craving)", name: "4-7-8 Technique", detail: "Inhale 4s · Hold 7s · Exhale 8s — 3 cycles. Stops cravings."),
        BreathingSlot(icon: "😴", time: "Bedtime",           name: "Extended Exhale", detail: "Inhale 4s · Exhale 8s — repeat until drowsy"),
    ]

    static let meals: [Meal] = [
        Meal(name: "🌅 Breakfast",          time: "7:00 – 8:30 AM",  kcal: "~480 kcal"),
        Meal(name: "☀️ Lunch",              time: "12:30 – 2:00 PM", kcal: "~560 kcal"),
        Meal(name: "🍎 Snack",              time: "3:30 – 4:30 PM",  kcal: "~200 kcal"),
        Meal(name: "🌆 Dinner",             time: "7:00 – 8:00 PM",  kcal: "~480 kcal"),
        Meal(name: "🌙 Evening (optional)", time: "before 9:00 PM",  kcal: "~130 kcal"),
    ]

    static let kitchenClosesHour = 21
    static let maxWaterPerDay = 5000
}
