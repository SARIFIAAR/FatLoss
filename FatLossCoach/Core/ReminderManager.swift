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
        let settings = store.data.reminders
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("water-") || $0.hasPrefix("walk-") })
        guard settings.waterOn || settings.walkOn, permission == .granted else { return }

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
        }

        for r in requests.prefix(60) { try? await center.add(r) }
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
