import Foundation

/// Plain-language daily guidance derived from the day's scores. Shared by the Today summary
/// and the Body "Your Day" card so the message stays consistent (and is the future home of the
/// AI coach — same copy slot, smarter text later).
enum DayCoach {
    static func message(_ s: BodyDayScores) -> (headline: String, body: String) {
        guard let rec = s.recovery else {
            return ("Building your baseline",
                    "Wear your watch to bed for a few nights and your daily guidance will appear here.")
        }
        let debt = s.sleepNeed.total - (s.day.sleepH ?? s.sleepNeed.total)
        let sleepLine = debt > 1 ? " You're carrying some sleep debt — an earlier night would help." : ""
        switch rec.zone {
        case .green:
            return ("Primed to push",
                    "Recovery is strong today — a great day to train hard. Aim for the higher end of your strain target and fuel well." + sleepLine)
        case .yellow:
            return ("Train with intent",
                    "You're balanced. A moderate session is ideal — keep effort controlled and protect tonight's sleep." + sleepLine)
        case .red:
            return ("Prioritise rest",
                    "Recovery is low. Keep strain light — your body wants fuel and sleep, not another hard demand. Pushing now would feel harder and set you back." + sleepLine)
        }
    }
}

extension Notification.Name {
    /// Posted by the Today summary to jump to the Body tab.
    static let openBody = Notification.Name("openBody")
    /// Posted by the Today nutrition card to jump to the Nutrition tab.
    static let openNutrition = Notification.Name("openNutrition")
    /// Posted by the Today phase strip to jump to the Train tab (the programme / phases builder).
    static let openTrain = Notification.Name("openTrain")
}
