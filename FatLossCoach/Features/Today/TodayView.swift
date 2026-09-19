import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    // Profile lost its tab slot (Body took it); it lives in a sheet behind the gear now.
    @State private var showProfile = UserDefaults.standard.integer(forKey: "startTab") == 4

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning!" : h < 17 ? "Good afternoon!" : "Good evening!"
    }
    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        Screen(subtitle: dateLine, title: greeting) {
            DaySummaryCard()
            PhaseStrip()
            TargetsCard()
            WatchCard()
            HabitsCard()
            WaterCard()
            CoffeeCard()
            SupplementsCard()
            BreathingCard()
        }
        .overlay(alignment: .topTrailing) {
            Button { showProfile = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .padding(.trailing, 10)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showProfile) { ProfileView() }
    }
}

// MARK: - Cards

/// Compact "where am I in the programme" strip.
struct PhaseStrip: View {
    @Environment(Store.self) private var store
    var body: some View {
        let phase = store.currentPhase
        let prog = store.phaseProgress
        Card(padding: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Phase \(phase.number) · \(phase.name)")
                    .font(Theme.scoreS).foregroundStyle(Theme.text)
                Spacer()
                Text(prog.started ? "Week \(prog.week) of \(prog.totalWeeks)" : "Not started")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(prog.started ? Theme.primary : Theme.orange)
            }
            PhaseTrack(compact: true).padding(.top, 8)
            if !prog.started {
                Button("︎ Start Phase \(phase.number) today") { store.startCurrentPhase() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .padding(.top, 10)
            } else if prog.isComplete, phase.number < Plan.phases.count {
                Button("Advance to Phase \(phase.number + 1)") { store.advancePhase() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.orange, compact: true))
                    .padding(.top, 10)
            }
        }
    }
}

struct TargetsCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        let g = store.data.goals
        let t = store.totals()
        let eaten = Int(t.kcal.rounded())
        let over = eaten > g.kcal
        let left = abs(g.kcal - eaten)
        let frac = g.kcal > 0 ? min(1, t.kcal / Double(g.kcal)) : 0
        Button { NotificationCenter.default.post(name: .openNutrition, object: nil) } label: {
            Card(accent: over ? Theme.red : Theme.primary) {
                HStack {
                    Text("NUTRITION").font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 6)
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 8)
                        Circle().trim(from: 0, to: max(0.001, frac))
                            .stroke(over ? Theme.red : Theme.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: (over ? Theme.red : Theme.primary).opacity(0.5), radius: 5)
                        VStack(spacing: 0) {
                            Text("\(left)").font(W.score(24)).foregroundStyle(Theme.text)
                            Text(over ? "over" : "left").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 88, height: 88)
                    VStack(spacing: 8) {
                        macroLine("Protein", t.protein, g.protein, Theme.primary)
                        macroLine("Carbs", t.carbs, g.carbs, Theme.orange)
                        macroLine("Fat", t.fat, g.fat, Theme.blue)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func macroLine(_ name: String, _ value: Double, _ goal: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(value.rounded()))/\(goal)g").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card2)
                    Capsule().fill(color).frame(width: max(3, geo.size.width * min(1, goal > 0 ? value / Double(goal) : 0)))
                }
            }
            .frame(height: 5)
        }
    }
}

struct MacroStat: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.scoreM).foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WatchCard: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        let h = store.healthToday
        let goal = Double(store.data.goals.stepsGoal)
        Card {
            SectionTitle("Apple Watch Today")
            HStack(spacing: 12) {
                StatBox {
                    Text((h?.steps ?? 0).formatted())
                        .font(Theme.titleL).foregroundStyle(Theme.primary)
                    Text("steps").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    ProgressBar(value: Double(h?.steps ?? 0) / goal, height: 8)
                        .padding(.top, 3)
                    Text("Goal: \(store.data.goals.stepsGoal.formatted())")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatBox {
                    Text(h?.burnedKcal.map { "\(Int($0.rounded()))" } ?? "–")
                        .font(Theme.titleL).foregroundStyle(Theme.orange)
                    Text("kcal burned").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text(h?.activeKcal.map { "\(Int($0.rounded())) active" }
                         ?? (health.hasConnected ? "No reading yet" : "Connect Health in Profile"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 3)
                }
                StatBox {
                    Text(h?.restingHR.map { "\(Int($0.rounded()))" } ?? "–")
                        .font(Theme.titleL).foregroundStyle(Theme.primary)
                    Text("resting HR").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text(h?.restingHR != nil ? "bpm" : (health.hasConnected ? "No reading yet" : "Connect Health"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 3)
                }
            }
            let e = store.energy()
            if let burned = e.burned {
                let net = burned - e.eaten
                Text(e.eaten > 0
                     ? "Burned \(Int(burned)) · eaten \(Int(e.eaten)) · \(net >= 0 ? "deficit" : "surplus") \(Int(abs(net))) kcal so far"
                     : "Burned \(Int(burned)) kcal so far · scan a meal to see today's deficit")
                    .font(.system(size: 12)).foregroundStyle(net >= 0 || e.eaten == 0 ? Theme.muted : Theme.red)
                    .padding(.top, 8)
            }
        }
    }
}

/// The day at a glance: coaching line + the four headline scores (tap → Body) + mood.
/// Replaces the old "Recovery & Readiness" card (which duplicated the Body dashboard).
struct DaySummaryCard: View {
    @Environment(Store.self) private var store
    private let moodIcons = ["cloud.rain.fill", "cloud.fill", "cloud.sun.fill", "sun.max.fill", "sparkles"]
    private let moodColors: [Color] = [Theme.red, Theme.orange, Theme.orange, Theme.primaryLight, Theme.primary]

    var body: some View {
        let s = store.bodyDay()
        let c = DayCoach.message(s)
        let recColor = s.recovery.map { Readiness.color($0.score) } ?? Theme.muted
        let rec = store.recoveryToday
        Card(accent: s.recovery.map { Readiness.color($0.score) }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.primary)
                Text("YOUR DAY").font(.system(size: 11, weight: .bold)).kerning(1.2).foregroundStyle(Theme.muted)
                Spacer()
                Button { NotificationCenter.default.post(name: .openBody, object: nil) } label: {
                    HStack(spacing: 3) {
                        Text("Details").font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }.foregroundStyle(Theme.primary)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                if let hs = s.humansScore {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 7)
                        Circle().trim(from: 0, to: max(0.001, Double(hs) / 100))
                            .stroke(Readiness.color(hs), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Readiness.color(hs).opacity(0.5), radius: 5)
                        VStack(spacing: -2) {
                            Text("\(hs)").font(W.score(26)).foregroundStyle(Theme.text)
                            Text("SCORE").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if s.humansScore != nil {
                        Text(s.humansScoreLabel).font(.system(size: 12, weight: .heavy)).foregroundStyle(Readiness.color(s.humansScore ?? 0))
                    }
                    Text(c.headline).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text)
                    Text(c.body).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 10)

            Button { NotificationCenter.default.post(name: .openBody, object: nil) } label: {
                HStack(spacing: 8) {
                    scoreChip("Recovery", s.recovery.map { "\($0.score)" } ?? "–", recColor)
                    scoreChip("Strain", s.strain.score > 0 ? String(format: "%.1f", s.strain.score) : "–", Theme.blue)
                    scoreChip("Sleep", s.sleepPerformance.map { "\(Int($0.rounded()))%" } ?? "–", Theme.blue)
                    scoreChip("Battery", s.battery.map { "\($0.level)" } ?? "–", Theme.primary)
                }
                .padding(.top, 12)
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.border).padding(.vertical, 12)
            HStack {
                Text("Today's Mood").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { m in
                        let sel = rec.mood == m
                        Button { store.setMood(m) } label: {
                            Image(systemName: moodIcons[m - 1])
                                .font(.system(size: 17))
                                .foregroundStyle(sel ? moodColors[m - 1] : Theme.muted)
                                .frame(width: 34, height: 30)
                                .background(sel ? moodColors[m - 1].opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scoreChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(Theme.score(22)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).kerning(0.5).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


struct WaterCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        let ml = store.waterToday
        let goal = store.data.goals.waterGoal
        Card {
            SectionTitle("Water")
            HStack {
                Text("\(ml) ml").font(Theme.scoreM).foregroundStyle(Theme.primary)
                Spacer()
                Text("Goal: \(goal.formatted()) ml").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            ProgressBar(value: Double(ml) / Double(goal), height: 18,
                        fill: AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.blue], startPoint: .leading, endPoint: .trailing)))
                .padding(.vertical, 8)
            Button("+ 250 ml") { store.addWater(250) }.buttonStyle(PillButtonStyle())
        }
    }
}

struct SupplementsCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        Card {
            SectionTitle("Supplements")
            VStack(spacing: 0) {
                ForEach(Array(Plan.supplements.enumerated()), id: \.element.id) { i, s in
                    let taken = store.isSupplementTaken(s.key)
                    Button { store.toggleSupplement(s.key) } label: {
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(taken ? Theme.orange : Color.clear)
                                .overlay(Capsule().stroke(Theme.orange, lineWidth: 2))
                                .frame(width: 32, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                (Text(s.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                 + Text(" \(s.dose)").font(.system(size: 12)).foregroundStyle(Theme.muted))
                                Text(s.when).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if taken {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < Plan.supplements.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }
}

/// Breathing schedule: tap a row to start the guided session (circle + voice + haptics); the tick on the
/// right still lets you mark one done by hand.
struct BreathingCard: View {
    @Environment(Store.self) private var store
    @State private var session: BreathingSlot?
    var body: some View {
        Card {
            SectionTitle("Breathing Schedule")
            Text("Tap a session to be guided through it.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(Plan.breathing.enumerated()), id: \.element.id) { i, b in
                    let done = store.isBreathingDone(b.name)
                    HStack(alignment: .center, spacing: 10) {
                        Button { session = b } label: {
                            HStack(alignment: .center, spacing: 10) {
                                ZStack {
                                    Circle().fill(done ? Theme.border : Theme.primary.opacity(0.12)).frame(width: 40, height: 40)
                                    Text(b.icon).font(.system(size: 20))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.time).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.primary)
                                    HStack(spacing: 6) {
                                        Text(b.name).font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(done ? Theme.muted : Theme.text)
                                            .strikethrough(done, color: Theme.muted)
                                        Image(systemName: "play.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.primaryLight)
                                    }
                                    Text(b.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 6)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { store.toggleBreathing(b.name) } label: { CheckMark(done: done) }
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 9)
                    if i < Plan.breathing.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
        .fullScreenCover(item: $session) { slot in
            BreathingSessionView(slot: slot)
        }
        // Debug / screenshots: `-breathing "Box Breathing"` opens that session; add `-breathingStart 1` to auto-start.
        .onAppear {
            if session == nil, let name = UserDefaults.standard.string(forKey: "breathing"), let slot = Plan.breathing.first(where: { $0.name == name }) {
                session = slot
            }
        }
    }
}
