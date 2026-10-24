import SwiftUI

/// Apple Workout-app palette (used only on the tracker screens, on purpose — it's the visual
/// language users already know from the Watch: lime elapsed time, red heart, cyan distance).
private enum WK {
    static let lime   = Color(hex: 0xA9F36E)   // elapsed time / workout time
    static let red    = Color(hex: 0xFF4F6D)   // heart rate
    static let cyan   = Color(hex: 0x6EE6F3)   // distance / pace
    static let orange = Color(hex: 0xFFA852)   // active energy
    static let purple = Color(hex: 0xC48AF9)   // VO2 estimate
}

/// "Track a workout" card on the Train tab — pick a type, get an Apple-Watch-style live session
/// (timer, ring HR, GPS distance/pace, kcal) and an Apple-Fitness-style summary when you finish.
struct WorkoutTrackerCard: View {
    @Environment(Store.self) private var store
    @Environment(QRingManager.self) private var qring
    @State private var session = WorkoutSession()
    @State private var showSession = false

    var body: some View {
        Card {
            SectionTitle("Track a workout")
            Text(qring.connected != nil
                 ? "Live heart rate from your HUMANS Ring · GPS pace from your phone"
                 : "GPS pace from your phone — connect your HUMANS Ring for live heart rate")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(2)
            HStack(spacing: 8) {
                ForEach(WorkoutSession.Kind.allCases) { kind in
                    Button {
                        session.start(kind, store: store, ring: qring)
                        showSession = true
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.icon).font(.system(size: 17, weight: .semibold))
                            Text(kind.rawValue).font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card2))
                        .foregroundStyle(Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .fullScreenCover(isPresented: $showSession) {
            WorkoutSessionView(session: session)
        }
        .onAppear {
#if DEBUG
            // Screenshot harness: -trackWorkout Run (+ -workoutDemo 1 to pre-fill values).
            if !showSession, let raw = UserDefaults.standard.string(forKey: "trackWorkout"),
               let k = WorkoutSession.Kind(rawValue: raw) {
                session.start(k, store: store, ring: qring)
                if UserDefaults.standard.bool(forKey: "workoutDemo") { session.demoFill() }
                showSession = true
            }
#endif
        }
    }
}

/// Live session — the Apple Watch Workout screen, phone-sized: left-aligned stack of big
/// condensed metrics, lime timer on top, round end/discard controls at the bottom.
struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QRingManager.self) private var qring
    var session: WorkoutSession
    @State private var summary: WorkoutSession.Summary?
    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let s = summary {
                WorkoutSummaryView(summary: s) { dismiss() }
            } else {
                liveScreen
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
#if DEBUG
            if UserDefaults.standard.bool(forKey: "workoutSummary") {
                summary = WorkoutSession.demoSummary
            }
#endif
        }
    }

    private var liveScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(session.kind.rawValue, systemImage: session.kind.icon)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if qring.connected != nil {
                    Label("Ring", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.primary)
                }
            }
            .padding(.top, 18)

            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                metric(timeString, unit: nil, label: "Elapsed", color: WK.lime, size: 64)
                metric(session.currentHR.map { "\($0)" } ?? "--", unit: "BPM",
                       label: "Heart Rate", color: WK.red, icon: "heart.fill")
                metric(String(format: "%.0f", session.kcal), unit: "CAL", label: "Active Energy",
                       color: WK.orange)
                if session.kind.usesGPS {
                    metric(String(format: "%.2f", session.distanceM / 1000), unit: "KM",
                           label: "Distance", color: WK.cyan)
                    metric(paceString, unit: "/KM", label: "Current Pace", color: WK.cyan)
                }
            }

            if session.gpsAuthDenied, session.kind.usesGPS {
                Text("Location is off — distance and pace won't record. Enable it in Settings → Privacy.")
                    .font(.system(size: 11)).foregroundStyle(WK.orange).padding(.top, 14)
            }

            Spacer()

            HStack(spacing: 40) {
                Spacer()
                roundControl("xmark", label: "Discard", color: Theme.card2, fg: Theme.text) {
                    confirmDiscard = true
                }
                roundControl("stop.fill", label: "End", color: WK.red, fg: .black) {
                    summary = session.end(save: true)
                    if summary == nil { dismiss() }
                }
                Spacer()
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 26)
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { _ = session.end(save: false); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private func metric(_ value: String, unit: String?, label: String, color: Color,
                        icon: String? = nil, size: CGFloat = 46) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(Theme.score(size)).foregroundStyle(color)
                    .monospacedDigit().contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.system(size: 15, weight: .heavy)).foregroundStyle(color.opacity(0.75))
                }
                if let icon {
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.muted)
        }
    }

    private func roundControl(_ icon: String, label: String, color: Color, fg: Color,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(fg)
                    .frame(width: 66, height: 66).background(Circle().fill(color))
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
        }
    }

    private var timeString: String {
        let s = Int(session.elapsed)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var paceString: String {
        guard let p = session.paceMinPerKm, p < 60 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(p), Int(p.truncatingRemainder(dividingBy: 1) * 60))
    }
}

/// Post-workout summary — the Apple Fitness "Workout Details" layout: a 2-column grid of
/// label-over-colored-value stats with hairline dividers.
struct WorkoutSummaryView: View {
    var summary: WorkoutSession.Summary
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.entry.name)
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.text)
                .padding(.top, 26)
            Text(summary.saved ? "Saved to your day — feeds Strain & Physical Age"
                               : "Under a minute — not saved")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 2)

            Text("WORKOUT DETAILS")
                .font(.system(size: 11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Theme.muted).padding(.top, 26).padding(.bottom, 10)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
                GridRow {
                    detail("Workout Time", timeText, WK.lime)
                    detail("Active Calories", summary.entry.kcal.map { String(format: "%.0f CAL", $0) } ?? "--", WK.orange)
                }
                divider
                GridRow {
                    detail("Distance", summary.distanceM > 0 ? String(format: "%.2f KM", summary.distanceM / 1000) : "--", WK.cyan)
                    detail("Avg. Pace", paceText, WK.cyan)
                }
                divider
                GridRow {
                    detail("Avg. Heart Rate", summary.entry.avgHR.map { String(format: "%.0f BPM", $0) } ?? "--", WK.red)
                    detail("Max. Heart Rate", summary.entry.maxHR.map { String(format: "%.0f BPM", $0) } ?? "--", WK.red)
                }
                if let vo2 = summary.vo2Est {
                    divider
                    GridRow {
                        detail("Est. VO₂ Max", String(format: "%.0f", vo2), WK.purple)
                        detail("", "", .clear)
                    }
                }
            }

            if summary.vo2Est != nil {
                Text("VO₂ max estimated from your pace and heart rate — a fitness trend, not a medical measurement.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(2).padding(.top, 14)
            }

            Spacer()

            Button(action: onDone) { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 26)
        }
        .padding(.horizontal, 26)
    }

    private var divider: some View {
        Rectangle().fill(Theme.card2).frame(height: 1).padding(.vertical, 12)
    }

    private func detail(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.score(24)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeText: String {
        let s = Int(summary.entry.minutes * 60)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    private var paceText: String {
        guard let p = summary.paceMinPerKm, p < 60 else { return "--" }
        return String(format: "%d'%02d\"", Int(p), Int(p.truncatingRemainder(dividingBy: 1) * 60))
    }
}
