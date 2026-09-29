import Foundation

// MARK: - PARKED: legacy static 3-phase programme (Foundation → Build → Full Gym)
//
// This is the ORIGINAL static programme, ported 1:1 from the web app. As of the
// Physical-Age-engine change it is NO LONGER the driver of the Workout/Train tab — that tab
// now generates the week from `BodyMetrics.weeklyProgramme`. This content is PARKED here,
// intact and fully recoverable, not deleted.
//
// It is still live for two non-driver purposes so the wider app keeps compiling and behaving:
//   • `Plan.phase(_:)` / `Plan.phases` are thin shims (in Constants.swift) that delegate here,
//     so `Store.currentPhase` / `phaseProgress` / the Today PhaseStrip / ProfileView /
//     ReminderManager's training-weekday derivation continue to work unchanged.
//   • It remains the exercise catalogue the progressive-overload lift logging references.
//
// TO FULLY RESTORE the 3-phase programme as the Workout-tab driver: in WorkoutView.swift, swap
// `PhysicalAgePlanView` back for the phase-based body (PhaseCard + per-day schedule) — the old
// view code is preserved in `Legacy/LegacyWorkoutView.swift`. Nothing else needs to change; the
// data (`data.program.phase`/`startDate`) and these definitions never went away.
enum LegacyPlan {

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
              tip: "Pick a weight you can lift for the top of the range with 2 reps in reserve. Hit the top for 2 sessions add 2.5 kg.",
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
}
