import Foundation
import Observation
import UserNotifications
import UIKit

/// Water and walk nudges as local notifications — no server, no push certificates.
/// Everything is re-planned (next 3 days) whenever the app comes to the foreground, water is logged,
/// Health syncs or the settings change, so each reminder carries today's real progress
/// ("1,250 / 3,000 ml", "4,200 of 8,000 steps") and disappears once the goal is met.
@Observable
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    enum Permission { case unknown, granted, denied }
    var permission: Permission = .unknown

    private weak var store: Store?
    private var planTask: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private static let daysAhead = 3

    static let waterCategory = "WATER"
    static let walkCategory = "WALK"

    func attach(store: Store) {
        self.store = store
        center.delegate = self
        let add250 = UNNotificationAction(identifier: "water-250", title: "Log 250 ml", options: [])
        let add500 = UNNotificationAction(identifier: "water-500", title: "Log 500 ml", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.waterCategory, actions: [add250, add500], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.walkCategory, actions: [], intentIdentifiers: []),
        ])
        store.onWaterChange = { [weak self] in self?.schedulePlan() }
        refreshPermission()
    }

    func refreshPermission() {
        center.getNotificationSettings { [weak self] s in
            Task { @MainActor in
                switch s.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self?.permission = .granted
                case .denied: self?.permission = .denied
                default: self?.permission = .unknown
                }
            }
        }
    }

    /// Asks for permission if needed; returns whether notifications are allowed.
    @discardableResult
    func requestPermission() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permission = ok ? .granted : .denied
        return ok
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Fire one notification a day when a vital is out of the user's typical range (opt-in).
    func notifyHealthAlertsIfNeeded() {
        guard let store, store.data.reminders.healthAlertsPush else { return }
        let alerts = store.healthAlerts()
        guard !alerts.isEmpty else { return }
        let key = "health-alert-notified-\(store.today)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }   // once per day
        let content = UNMutableNotificationContent()
        content.title = alerts.count == 1 ? "A vital is off today" : "\(alerts.count) vitals are off today"
        content.body = alerts.prefix(3).map { "\($0.name) \($0.value) — \($0.detail)" }.joined(separator: "\n")
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "health-alerts", content: content, trigger: nil))
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Debounced: several triggers in a row (sync + water + foreground) become one re-plan.
    func schedulePlan() {
        planTask?.cancel()
        planTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            await self.plan()
        }
    }

    // MARK: Planning

    func plan() async {
        guard let store else { return }
        // Prune stale per-habit / per-supplement reminder entries before scheduling, so a deleted
        // habit or untracked supplement can never leave a dangling nudge.
        pruneStaleReminderEntries()
        let settings = store.data.reminders
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix("water-") || $0.hasPrefix("walk-") || $0.hasPrefix("meal-")
                || $0.hasPrefix("habit-") || $0.hasPrefix("supp-") || $0.hasPrefix("gym-")
        })
        guard permission == .granted else { return }

        // Per-habit, per-supplement and gym-day reminders repeat every day (or every training
        // weekday). They schedule independently of the interval-based water/walk/meals block below.
        scheduleFixedTimeReminders(settings)

        guard settings.waterOn || settings.walkOn || settings.mealsOn else { return }

        let cal = Calendar.current
        let now = Date()
        let goals = store.data.goals
        var requests: [UNNotificationRequest] = []

        for offset in 0..<Self.daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let isToday = offset == 0
            let key = DateKey.key(day)

            if settings.waterOn {
                let drank = isToday ? (store.data.water[key] ?? 0) : 0
                let remaining = goals.waterGoal - drank
                if remaining > 0 {
                    var minutes = settings.startHour * 60
                    let last = settings.endHour * 60
                    while minutes <= last {
                        if let fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), fire > now {
                            let content = UNMutableNotificationContent()
                            content.title = "Time for water 💧"
                            content.body = isToday
                                ? "\(drank.formatted()) / \(goals.waterGoal.formatted()) ml so far — \(remaining.formatted()) ml to go."
                                : "Keep the \(goals.waterGoal.formatted()) ml habit going. A glass now counts."
                            content.sound = .default
                            content.categoryIdentifier = Self.waterCategory
                            content.threadIdentifier = "water"
                            requests.append(UNNotificationRequest(identifier: "water-\(key)-\(minutes)",
                                                                  content: content, trigger: Self.trigger(fire, cal)))
                        }
                        minutes += max(30, settings.waterEveryMinutes)
                    }
                }
            }

            if settings.walkOn {
                let steps = isToday ? (store.data.health[key]?.steps ?? 0) : 0
                let left = goals.stepsGoal - steps
                if left > 0 {
                    for hour in settings.walkHours.sorted() {
                        guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
                        let content = UNMutableNotificationContent()
                        content.title = "Time for a walk 🚶"
                        content.body = isToday && steps > 0
                            ? "\(steps.formatted()) of \(goals.stepsGoal.formatted()) steps — \(left.formatted()) to go, about \(Self.minutes(forSteps: left)) min of walking."
                            : "Aim for \(goals.stepsGoal.formatted()) steps today. A brisk 20 minutes is ~2,500."
                        content.sound = .default
                        content.categoryIdentifier = Self.walkCategory
                        content.threadIdentifier = "walk"
                        requests.append(UNNotificationRequest(identifier: "walk-\(key)-\(hour)",
                                                              content: content, trigger: Self.trigger(fire, cal)))
                    }
                }
            }
            if settings.mealsOn {
                let names = ["Breakfast", "Lunch", "Dinner"]
                let loggedCount = isToday ? (store.data.meals[key]?.count ?? 0) : 0
                for (i, hour) in settings.mealHours.prefix(3).enumerated() {
                    guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
                    // On today, skip a meal nudge once enough meals are already logged.
                    if isToday && loggedCount > i { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "Log your \(names[min(i, 2)].lowercased()) 🍽️"
                    content.body = "Snap, say or scan it — keep your diary and calorie balance on track."
                    content.sound = .default
                    content.threadIdentifier = "meal"
                    requests.append(UNNotificationRequest(identifier: "meal-\(key)-\(hour)",
                                                          content: content, trigger: Self.trigger(fire, cal)))
                }
            }
        }

        for r in requests.prefix(60) { try? await center.add(r) }
    }

    // MARK: Fixed-time reminders (habits, supplements, gym days)

    /// Habit and supplement reminders repeat DAILY at the chosen minute-of-day; the workout reminder
    /// repeats only on the current phase's training weekdays. All are opt-in per item and only added
    /// when permission is granted (the caller already checked). Distinct id prefixes (habit-/supp-/gym-)
    /// let `plan()` clear them cleanly without touching water/walk/meals.
    private func scheduleFixedTimeReminders(_ settings: ReminderSettings) {
        guard let store else { return }

        // Habits — "Time to <habit name>", daily.
        let habitsById = Dictionary(uniqueKeysWithValues: store.habitDefs.map { ($0.id, $0) })
        for (id, minute) in settings.habitReminders {
            guard let def = habitsById[id] else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Time to \(def.name.lowercased())"
            content.body = "A quick check-in keeps your streak going."
            content.sound = .default
            content.threadIdentifier = "habit"
            center.add(UNNotificationRequest(identifier: "habit-\(id)",
                                             content: content,
                                             trigger: Self.dailyTrigger(minute: minute)))
        }

        // Supplements — "Take your <supplement name>", daily; add the timing hint when we have one.
        let suppsById = Dictionary(uniqueKeysWithValues: store.trackedSupplements.map { ($0.id, $0) })
        for (id, minute) in settings.supplementReminders {
            guard let s = suppsById[id] else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Take your \(s.name)"
            if let detail = s.detail { content.body = detail }
            content.sound = .default
            content.threadIdentifier = "supp"
            center.add(UNNotificationRequest(identifier: "supp-\(id)",
                                             content: content,
                                             trigger: Self.dailyTrigger(minute: minute)))
        }

        // Workout — fires only on the current programme phase's training weekdays.
        if settings.workoutOn {
            let phase = store.currentPhase
            let weekdays = phase.trainingDays.compactMap(Self.weekday(fromDay:))
            let days = weekdays.isEmpty ? Self.trainingWeekdays(count: store.data.intake?.trainingDays ?? 3) : weekdays
            for wd in Set(days) {
                let content = UNMutableNotificationContent()
                content.title = "Time to train — \(phase.name)"
                content.body = "Phase \(phase.number): \(phase.tagline). Log your lifts as you go."
                content.sound = .default
                content.threadIdentifier = "gym"
                center.add(UNNotificationRequest(identifier: "gym-\(wd)",
                                                 content: content,
                                                 trigger: Self.weekdayTrigger(weekday: wd, minute: settings.workoutMinute)))
            }
        }
    }

    /// Remove reminder entries whose habit / supplement no longer exists (write back to the store).
    private func pruneStaleReminderEntries() {
        guard let store else { return }
        let habitIds = Set(store.habitDefs.map(\.id))
        let suppIds = Set(store.trackedSupplements.map(\.id))
        var r = store.data.reminders
        let prunedHabits = r.habitReminders.filter { habitIds.contains($0.key) }
        let prunedSupps = r.supplementReminders.filter { suppIds.contains($0.key) }
        guard prunedHabits.count != r.habitReminders.count || prunedSupps.count != r.supplementReminders.count else { return }
        r.habitReminders = prunedHabits
        r.supplementReminders = prunedSupps
        store.data.reminders = r
    }

    /// A 3-letter day label ("Mon"…"Sun") → Calendar weekday (Sun = 1 … Sat = 7). nil if unknown.
    static func weekday(fromDay day: String) -> Int? {
        switch day.prefix(3).lowercased() {
        case "sun": return 1; case "mon": return 2; case "tue": return 3; case "wed": return 4
        case "thu": return 5; case "fri": return 6; case "sat": return 7; default: return nil
        }
    }

    /// Fallback training weekdays when the phase has no explicit schedule — Mon/Wed/Fri style spread.
    private static func trainingWeekdays(count: Int) -> [Int] {
        switch max(1, min(count, 6)) {
        case 1: return [2]
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 5, 6]
        case 5: return [2, 3, 4, 5, 6]
        default: return [2, 3, 4, 5, 6, 7]
        }
    }

    private static func dailyTrigger(minute: Int) -> UNCalendarNotificationTrigger {
        var comps = DateComponents()
        comps.hour = minute / 60
        comps.minute = minute % 60
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    private static func weekdayTrigger(weekday: Int, minute: Int) -> UNCalendarNotificationTrigger {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = minute / 60
        comps.minute = minute % 60
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    private static func trigger(_ date: Date, _ cal: Calendar) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                                      repeats: false)
    }

    private static func minutes(forSteps steps: Int) -> Int { max(5, Int((Double(steps) / 110).rounded())) }

    // MARK: Delegate

    /// Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            switch response.actionIdentifier {
            case "water-250": store?.addWater(250)
            case "water-500": store?.addWater(500)
            default: break
            }
        }
    }
}
