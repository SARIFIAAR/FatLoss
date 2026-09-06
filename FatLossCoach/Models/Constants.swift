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

struct Phase: Identifiable, Hashable {
    let number: Int          // 1...3
    let name: String         // "Foundation"
    let tagline: String      // shown in the Workout header
    let weeks: Int           // planned length
    let goal: String         // what this phase is for
    let tip: String          // progression rule for this phase
    let workouts: [WorkoutDay]
    var id: Int { number }
    var trainingDays: [String] { workouts.filter(\.isTraining).map(\.day) }
}

struct BreathingSlot: Identifiable {
    let icon: String
    let time: String
    let name: String
    let detail: String
    var id: String { name }
}

struct Meal: Identifiable {
    let key: String          // "breakfast"
    let name: String
    let time: String
    let targetKcal: Int
    var id: String { key }
    var kcal: String { "~\(targetKcal) kcal" }
}

/// Static programme content, ported 1:1 from the web app.
enum Plan {
    static let habits: [Habit] = [
        Habit(key: "walk",    label: "Morning Walk 🚶",        time: "30–45 min"),
        Habit(key: "workout", label: "Workout Done 🏋️",       time: "Mon/Wed/Fri"),
        Habit(key: "water",   label: "Water 3L 💧",            time: "all day"),
        Habit(key: "kitchen", label: "Kitchen Closed 9pm 🌙",  time: "9:00 PM"),
        Habit(key: "breath",  label: "Breathing Exercise 🌬️", time: "any time"),
        Habit(key: "supps",   label: "Supplements Taken 💊",   time: "D3 · Omega-3 · Mg"),
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

    // MARK: Programme phases

    static let phases: [Phase] = [
        Phase(number: 1, name: "Foundation", tagline: "Build the habit", weeks: 4,
              goal: "Two short full-body sessions a week (home or gym) plus a daily walk. The goal is consistency, not intensity.",
              tip: "Form over weight. Stop 2 reps short of failure. Add 1–2 reps per session before you add any load.",
              workouts: [
            WorkoutDay(day: "Mon", label: "Full Body A", tag: "Legs · Push · Core", exercises: foundation),
            WorkoutDay(day: "Tue", label: "Walk", tag: "30–45 min brisk", exercises: []),
            WorkoutDay(day: "Wed", label: "Walk", tag: "30–45 min brisk", exercises: []),
            WorkoutDay(day: "Thu", label: "Full Body B", tag: "Legs · Pull · Core", exercises: foundation),
            WorkoutDay(day: "Fri", label: "Walk", tag: "30–45 min brisk", exercises: []),
            WorkoutDay(day: "Sat", label: "Active Recovery", tag: "Walk or stretch", exercises: []),
            WorkoutDay(day: "Sun", label: "Rest", tag: "Full rest day", exercises: []),
        ]),
        Phase(number: 2, name: "Build", tagline: "Learn the gym", weeks: 4,
              goal: "Three machine-first gym sessions. Learn each movement with light loads and build work capacity.",
              tip: "Pick a weight you can lift for the top of the range with 2 reps in reserve. Hit the top for 2 sessions → add 2.5 kg.",
              workouts: [
            WorkoutDay(day: "Mon", label: "Upper A", tag: "Chest · Back · Shoulders", exercises: [
                Exercise("Machine Chest Press",    "3×10–12", "Chest, Triceps",        "Machine_Bench_Press"),
                Exercise("Lat Pulldown",           "3×10–12", "Lats, Biceps",          "Wide-Grip_Lat_Pulldown"),
                Exercise("Machine Shoulder Press", "3×10–12", "Shoulders",             "Machine_Shoulder_Military_Press"),
                Exercise("Seated Cable Row",       "3×10–12", "Mid Back",              "Seated_Cable_Rows"),
                Exercise("Plank",                  "3×30s",   "Core",                  "Plank"),
            ]),
            WorkoutDay(day: "Tue", label: "Walk", tag: "30–45 min brisk", exercises: []),
            WorkoutDay(day: "Wed", label: "Lower", tag: "Legs · Glutes · Core", exercises: [
                Exercise("Leg Press (machine)",    "3×12–15", "Quads, Glutes",         "Leg_Press"),
                Exercise("Seated Leg Curl",        "3×12–15", "Hamstrings",            "Seated_Leg_Curl"),
                Exercise("Leg Extension",          "3×12–15", "Quads",                 "Leg_Extensions"),
                Exercise("Goblet Squat",           "3×10–12", "Quads, Glutes",         "Goblet_Squat"),
                Exercise("Standing Calf Raises",   "3×15",    "Calves",                "Standing_Calf_Raises"),
                Exercise("Dead Bug",               "3×10/side", "Core",                "Dead_Bug"),
            ]),
            WorkoutDay(day: "Thu", label: "Walk", tag: "30–45 min brisk", exercises: []),
            WorkoutDay(day: "Fri", label: "Upper B", tag: "Push · Pull · Arms", exercises: [
                Exercise("Push-Ups",               "3×8–12",  "Chest, Triceps",        "Pushups"),
                Exercise("Seated Cable Row",       "3×10–12", "Mid Back",              "Seated_Cable_Rows"),
                Exercise("Face Pulls",             "3×15",    "Rear Delt, Upper Back", "Face_Pull"),
                Exercise("DB Bicep Curls",         "3×10–12", "Biceps",                "Dumbbell_Bicep_Curl"),
                Exercise("Tricep Pushdowns",       "3×12–15", "Triceps",               "Triceps_Pushdown"),
                Exercise("Side Plank",             "3×20s/side", "Obliques",           "Side_Bridge"),
            ]),
            WorkoutDay(day: "Sat", label: "Active Recovery", tag: "Walk 30–45 min", exercises: []),
            WorkoutDay(day: "Sun", label: "Rest", tag: "Full rest day", exercises: []),
        ]),
        Phase(number: 3, name: "Full Gym", tagline: "Progressive overload", weeks: 8,
              goal: "Push / Pull / Legs with free weights. Chase small weekly progress on every lift.",
              tip: "When you complete all reps at the top of your range for 2 sessions in a row, add weight next time. Upper body: +2.5 kg · Lower body: +5 kg",
              workouts: fullGym),
    ]

    private static let foundation: [Exercise] = [
        Exercise("Bodyweight Squat",   "3×10–15",   "Quads, Glutes",      "Bodyweight_Squat"),
        Exercise("Incline Push-Up",    "3×8–12",    "Chest, Triceps",     "Incline_Push-Up"),
        Exercise("Glute Bridge",       "3×12–15",   "Glutes, Hamstrings", "Butt_Lift_Bridge"),
        Exercise("DB Bent-Over Row",   "3×10–12",   "Back, Biceps",       "Bent_Over_Two-Dumbbell_Row"),
        Exercise("Dead Bug",           "3×8/side",  "Core",               "Dead_Bug"),
        Exercise("Plank",              "3×20–30s",  "Core",               "Plank"),
    ]

    static func phase(_ n: Int) -> Phase { phases.first { $0.number == n } ?? phases[0] }

    /// Phase 3 programme (the original web app schedule).
    private static let fullGym: [WorkoutDay] = [
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
        Meal(key: "breakfast", name: "🌅 Breakfast",          time: "7:00 – 8:30 AM",  targetKcal: 480),
        Meal(key: "lunch",     name: "☀️ Lunch",              time: "12:30 – 2:00 PM", targetKcal: 560),
        Meal(key: "snack",     name: "🍎 Snack",              time: "3:30 – 4:30 PM",  targetKcal: 200),
        Meal(key: "dinner",    name: "🌆 Dinner",             time: "7:00 – 8:00 PM",  targetKcal: 480),
        Meal(key: "evening",   name: "🌙 Evening (optional)", time: "before 9:00 PM",  targetKcal: 130),
    ]
    static func meal(_ key: String?) -> Meal? { meals.first { $0.key == key } }

    static let kitchenClosesHour = 21
    static let maxWaterPerDay = 5000
}
