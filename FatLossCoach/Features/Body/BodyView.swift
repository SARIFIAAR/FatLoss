import SwiftUI

/// Dark performance dashboard in the style of wearable apps: a week calendar strip with
/// recovery-zone dots, three ring gauges (sleep / recovery / strain) and flat detail cards.
/// Always dark, independent of system theme. Tapping a gauge or card opens the pillar deep-dive.
enum W {
    static let bg      = Color(hex: 0x101518)
    static let card    = Color(hex: 0x1A2227)
    static let card2   = Color(hex: 0x232E35)
    static let divider = Color.white.opacity(0.07)
    static let text    = Color.white
    static let muted   = Color(hex: 0x7A8B94)
    static let green   = Color(hex: 0x43CB00)
    static let yellow  = Color(hex: 0xF0C930)
    static let red     = Color(hex: 0xFF0026)
    static let blue    = Color(hex: 0x0093E7)
    static let sleep   = Color(hex: 0x7BA1BB)
    static let vibrant = Color(hex: 0x42B883)

    static func recoveryColor(_ zone: BodyMetrics.Recovery.Zone) -> Color {
        switch zone { case .red: red; case .yellow: yellow; case .green: green }
    }
    /// Big score numerals: heavy + condensed system face (DIN-like without bundling a font).
    static func score(_ size: CGFloat) -> Font {
        Font(UIFont.systemFont(ofSize: size, weight: .heavy, width: .condensed))
    }
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .bold) }
}

enum Pillar: String, Identifiable {
    case sleep, recovery, strain
    var id: String { rawValue }
}

struct BodyView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var health
    @State private var dayOffset = 0        // 0 = today, positive = days back
    @State private var pillar: Pillar?
    @State private var impacts: [BehaviorImpact] = []
    @State private var week: WeekReport?

    private var dateKey: String { DateKey.key(DateKey.daysAgo(dayOffset)) }
    private var scores: BodyDayScores { store.bodyDay(dateKey) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    header
                    calendarStrip
                    healthAlertsCard
                    bodyBatteryCard
                    gaugeRow
                    if scores.recovery == nil { calibratingCard }
                    recoveryCard
                    stressCard.id("stress")
                    sleepCard
                    strainCard.id("strain")
                    vitalsCard.id("week")
                    bodyCompositionCard
                    BodyCompTrackerCard()
                    impactsCard
                    weekReportCard.id("report")
                    hrZonesCard
                    alertSettingsCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .onAppear {
                // Debug: `-bodyScroll strain|week` jumps to a card, `-bodyPillar sleep|recovery|strain`
                // opens a deep-dive (screenshot verification).
                if let target = UserDefaults.standard.string(forKey: "bodyScroll") {
                    proxy.scrollTo(target, anchor: .top)
                }
                if let p = UserDefaults.standard.string(forKey: "bodyPillar") {
                    pillar = Pillar(rawValue: p)
                }
            }
        }
        .task {
            // Both scan 60 days of scores; computed off the first frame.
            impacts = store.behaviorImpacts()
            week = store.weekReport()
        }
        .background(W.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $pillar) { p in
            PillarDetailView(pillar: p, dayOffset: dayOffset)
        }
    }

    // MARK: Header + calendar strip

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My Body").font(W.score(24)).foregroundStyle(W.text)
            Spacer()
            Text(dayOffset == 0 ? "Today" : dayLabel)
                .font(W.label(12)).kerning(0.5).foregroundStyle(W.muted)
        }
        .padding(.top, 6)
    }

    private var dayLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: DateKey.daysAgo(dayOffset))
    }

    /// Seven-day strip: weekday letter, day number, recovery-zone dot. Selected day is boxed.
    private var calendarStrip: some View {
        HStack(spacing: 5) {
            Button { dayOffset += 7 } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(W.muted).frame(width: 20, height: 44)
            }
            ForEach((0..<7).reversed(), id: \.self) { slot in
                let n = slot + max(0, dayOffset - 6)      // window slides when browsing back
                let day = DateKey.daysAgo(n)
                let s = store.bodyDay(DateKey.key(day))
                VStack(spacing: 3) {
                    Text(letter(day)).font(W.label(9)).foregroundStyle(W.muted)
                    Text(dayNum(day)).font(W.score(14))
                        .foregroundStyle(n == dayOffset ? W.text : W.muted)
                    Circle()
                        .fill(s.recovery.map { W.recoveryColor($0.zone) } ?? .clear)
                        .overlay(Circle().stroke(W.muted.opacity(s.recovery == nil ? 0.5 : 0), lineWidth: 1))
                        .frame(width: 7, height: 7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(n == dayOffset ? W.card2 : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { dayOffset = n }
            }
            Button { dayOffset = max(0, dayOffset - 7) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(dayOffset == 0 ? W.card2 : W.muted).frame(width: 20, height: 44)
            }
            .disabled(dayOffset == 0)
        }
    }

    private func letter(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: d)
    }
    private func dayNum(_ d: Date) -> String {
        String(Calendar.current.component(.day, from: d))
    }

    // MARK: Heart-rate zones (editable max HR + today's time-in-zone)

    @State private var editingMaxHR = false

    private var hrZonesCard: some View {
        let maxHR = store.maxHR
        let mins = store.zoneMinutes(on: dateKey)
        let peak = max(mins.max() ?? 0, 0.01)
        return DarkCard {
            HStack(alignment: .firstTextBaseline) {
                Text("HEART-RATE ZONES").font(W.label(12)).kerning(1.2).foregroundStyle(W.muted)
                Spacer()
                Button { editingMaxHR = true } label: {
                    Text("max \(maxHR) bpm").font(.system(size: 11)).foregroundStyle(W.blue)
                }
            }
            .padding(.bottom, 8)
            let colors = [W.sleep, W.vibrant, W.green, W.yellow, W.red]
            ForEach(BodyMetrics.hrZones, id: \.index) { z in
                let m = mins[z.index - 1]
                HStack(spacing: 8) {
                    Text(z.name).font(.system(size: 12)).foregroundStyle(W.text)
                        .frame(width: 128, alignment: .leading)
                    Text("\(z.low(maxHR))–\(z.high(maxHR))").font(.system(size: 10)).foregroundStyle(W.muted)
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(W.card2)
                            Capsule().fill(colors[z.index - 1])
                                .frame(width: m > 0 ? max(4, geo.size.width * m / peak) : 0)
                        }
                    }
                    .frame(height: 7)
                    Text(m > 0 ? "\(Int(m))m" : "–").font(W.score(13)).foregroundStyle(W.text)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
            Text("Zones are % of your max HR. Bars show today's minutes in each zone from workouts.")
                .font(.system(size: 10)).foregroundStyle(W.muted.opacity(0.7)).padding(.top, 4)
        }
        .sheet(isPresented: $editingMaxHR) { MaxHRSheet() }
    }

    // MARK: Health-alert push toggle

    @ViewBuilder private var alertSettingsCard: some View {
        @Bindable var s = store
        DarkCard {
            Toggle(isOn: Binding(
                get: { store.data.reminders.healthAlertsPush },
                set: { store.setHealthAlertsPush($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alert me to out-of-range vitals").font(.system(size: 14, weight: .semibold)).foregroundStyle(W.text)
                    Text("A notification when HRV, resting HR, temperature or SpO2 drift outside your typical range.")
                        .font(.system(size: 11)).foregroundStyle(W.muted)
                }
            }
            .tint(W.vibrant)
        }
    }

    // MARK: Health Alerts (out-of-range vitals, Heart-Analyzer style)

    @ViewBuilder private var healthAlertsCard: some View {
        let list = store.healthAlerts(on: dateKey)
        if !list.isEmpty {
            DarkCard {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14)).foregroundStyle(W.yellow)
                    Text("HEALTH ALERTS").font(W.label(11)).kerning(1).foregroundStyle(W.yellow)
                    Spacer()
                    Text("\(list.count)").font(W.label(11)).foregroundStyle(W.muted)
                }
                .padding(.bottom, 8)
                DividedRows(rows: list.map { a in
                    AnyView(
                        HStack {
                            Circle().fill(W.red).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.system(size: 13)).foregroundStyle(W.text)
                                Text(a.detail).font(.system(size: 11)).foregroundStyle(W.muted)
                            }
                            Spacer()
                            Text(a.value).font(W.score(16)).foregroundStyle(W.red)
                        }
                        .padding(.vertical, 8)
                    )
                })
            }
        }
    }

    // MARK: Body Battery (top of screen)

    private func batteryColor(_ zone: BodyMetrics.BodyBattery.Zone) -> Color {
        switch zone { case .high: W.green; case .medium: W.yellow; case .low: W.red }
    }

    @ViewBuilder private var bodyBatteryCard: some View {
        if let b = scores.battery {
            DarkCard {
                HStack(alignment: .center, spacing: 14) {
                    // battery glyph with fill
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).stroke(W.muted.opacity(0.4), lineWidth: 2)
                            .frame(width: 54, height: 26)
                        RoundedRectangle(cornerRadius: 3).fill(batteryColor(b.zone))
                            .frame(width: max(4, 48 * Double(b.level) / 100), height: 20)
                            .padding(.leading, 3)
                    }
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1).fill(W.muted.opacity(0.4))
                            .frame(width: 3, height: 10).offset(x: 4)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BODY BATTERY").font(W.label(10)).kerning(1).foregroundStyle(W.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(b.level)").font(W.score(30)).foregroundStyle(batteryColor(b.zone))
                            Text(b.label).font(.system(size: 13)).foregroundStyle(W.muted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(b.charge) charged").font(.system(size: 11)).foregroundStyle(W.green)
                        Text("−\(b.drained) spent").font(.system(size: 11)).foregroundStyle(W.muted)
                    }
                }
                Rectangle().fill(W.divider).frame(height: 1).padding(.vertical, 10)
                Text("Your energy in the tank right now — it fills with sleep and recovery, and drains with strain and stress.")
                    .font(.system(size: 11)).foregroundStyle(W.muted)
                HStack(spacing: 6) {
                    Image(systemName: batteryAdvice(b).icon).font(.system(size: 12)).foregroundStyle(batteryColor(b.zone))
                    Text(batteryAdvice(b).text).font(.system(size: 12, weight: .semibold)).foregroundStyle(W.text)
                }
                .padding(.top, 6)
            }
        }
    }

    /// Level-based recommendation, nuanced by what drained the battery (poor sleep vs hard training).
    private func batteryAdvice(_ b: BodyMetrics.BodyBattery) -> (icon: String, text: String) {
        let poorlyRested = b.charge < 60          // woke up under-charged → sleep was the limiter
        switch b.zone {
        case .high:
            return ("bolt.fill", "Fully charged — a great day to train hard or push your goals.")
        case .medium:
            return poorlyRested
                ? ("bed.double.fill", "Moderate — you woke a little low. Aim for an earlier night to top up.")
                : ("figure.walk", "Moderate energy — train, but keep it steady rather than all-out.")
        case .low:
            return poorlyRested
                ? ("bed.double.fill", "Running low, mostly from short sleep — prioritise rest and an early night.")
                : ("leaf.fill", "Depleted from today's load — go easy: light movement and recover.")
        }
    }

    // MARK: Gauges

    private var gaugeRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            RingGauge(title: "Sleep",
                      value: scores.sleepPerformance.map { "\(Int($0))%" } ?? "–",
                      fraction: (scores.sleepPerformance ?? 0) / 100,
                      color: W.sleep, size: 94)
                .onTapGesture { pillar = .sleep }
            RingGauge(title: "Recovery",
                      value: scores.recovery.map { "\($0.score)%" } ?? "–",
                      fraction: Double(scores.recovery?.score ?? 0) / 100,
                      color: scores.recovery.map { W.recoveryColor($0.zone) } ?? W.muted,
                      size: 130, valueSize: 40)
                .onTapGesture { pillar = .recovery }
            RingGauge(title: "Strain",
                      value: scores.strain.score > 0 ? String(format: "%.1f", scores.strain.score) : "–",
                      fraction: scores.strain.score / 21,
                      color: W.blue, size: 94)
                .onTapGesture { pillar = .strain }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var calibratingCard: some View {
        DarkCard {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(W.vibrant)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibrating").font(W.label(15)).foregroundStyle(W.text)
                    Text("Recovery unlocks after \(BodyMetrics.minCalibrationDays) nights of HRV data. Keep syncing Apple Health.")
                        .font(.system(size: 12)).foregroundStyle(W.muted)
                }
            }
        }
    }

    // MARK: Recovery card

    private var recoveryCard: some View {
        DarkCard {
            CardTitle("Recovery", scores.recovery.map {
                $0.zone == .green ? "Primed to push" : $0.zone == .yellow ? "Maintain today" : "Prioritise rest"
            } ?? "Waiting for data") { pillar = .recovery }
            DividedRows(rows: [
                AnyView(vitalRow("HRV", scores.day.hrv, unit: "ms", history: store.bodyHistory(\.hrv), higherIsBetter: true)),
                AnyView(vitalRow("Resting HR", scores.day.rhr, unit: "bpm", history: store.bodyHistory(\.rhr), higherIsBetter: false)),
                AnyView(vitalRow("Respiratory rate", scores.day.resp, unit: "rpm", history: store.bodyHistory(\.resp), higherIsBetter: nil)),
                AnyView(vitalRow("Sleep", scores.day.sleepH, unit: "h", history: store.bodyHistory(\.sleepH), higherIsBetter: true)),
            ])
        }
        .onTapGesture { pillar = .recovery }
    }

    // MARK: Stress (HRV-based autonomic activation)

    private func stressColor(_ zone: BodyMetrics.Stress.Zone) -> Color {
        switch zone { case .calm: W.green; case .balanced: W.yellow; case .elevated: W.red }
    }

    @ViewBuilder private var stressCard: some View {
        if let st = scores.stress {
            DarkCard {
                CardTitle("Stress", st.label, chevron: false) {}
                HStack(alignment: .firstTextBaseline) {
                    Text("\(st.score)").font(W.score(34)).foregroundStyle(stressColor(st.zone))
                    Text("/ 100").font(.system(size: 13)).foregroundStyle(W.muted)
                    Spacer()
                    Text(st.zone == .calm ? "Low autonomic load"
                         : st.zone == .balanced ? "Normal for you" : "Elevated — ease off")
                        .font(.system(size: 12)).foregroundStyle(W.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(W.card2)
                        Capsule().fill(stressColor(st.zone))
                            .frame(width: max(6, geo.size.width * Double(st.score) / 100))
                    }
                }
                .frame(height: 10)
                .padding(.top, 8)
                DividedRows(topPadding: 8, rows: [
                    AnyView(stressRow("HRV", st.hrvDrop)),
                    AnyView(stressRow("Resting HR", st.rhrRise)),
                    AnyView(stressRow("Respiratory rate", st.respRise)),
                ])
                stress7DayTable
                Text("HRV-based estimate of autonomic (sympathetic) load vs your 28-day baseline. Not a medical measurement.")
                    .font(.system(size: 10)).foregroundStyle(W.muted.opacity(0.7)).padding(.top, 6)
            }
        }
    }

    /// Last 7 days of stress as a labelled table: weekday, coloured bar, score.
    private var stress7DayTable: some View {
        VStack(spacing: 0) {
            Rectangle().fill(W.divider).frame(height: 1).padding(.vertical, 10)
            Text("LAST 7 DAYS").font(W.label(9)).kerning(0.8).foregroundStyle(W.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
            ForEach(0..<7, id: \.self) { n in            // today first, going back a week
                let day = DateKey.daysAgo(n)
                let s = store.bodyDay(DateKey.key(day)).stress
                HStack(spacing: 10) {
                    Text(weekdayShort(day)).font(.system(size: 12)).foregroundStyle(W.muted)
                        .frame(width: 38, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(W.card2)
                            if let s {
                                Capsule().fill(stressColor(s.zone))
                                    .frame(width: max(4, geo.size.width * Double(s.score) / 100))
                            }
                        }
                    }
                    .frame(height: 8)
                    Text(s.map { "\($0.score)" } ?? "–")
                        .font(W.score(15)).foregroundStyle(s.map { stressColor($0.zone) } ?? W.muted)
                        .frame(width: 34, alignment: .trailing)
                    Text(s?.label ?? "").font(.system(size: 10)).foregroundStyle(W.muted)
                        .frame(width: 64, alignment: .leading)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d)
    }

    /// One driver row: how much this signal is contributing to today's stress (0–1 → bar).
    private func stressRow(_ name: String, _ signal: Double?) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 13)).foregroundStyle(W.muted).frame(width: 120, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.card2)
                    if let s = signal {
                        Capsule().fill(s >= 0.6 ? W.red : s >= 0.4 ? W.yellow : W.green)
                            .frame(width: max(4, geo.size.width * s))
                    }
                }
            }
            .frame(height: 6)
            Text(signal.map { $0 >= 0.6 ? "high" : $0 >= 0.4 ? "mid" : "low" } ?? "–")
                .font(.system(size: 11)).foregroundStyle(W.muted).frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    /// today vs 28-day baseline, with an up/down arrow tinted by whether the move is good.
    private func vitalRow(_ name: String, _ value: Double?, unit: String,
                          history: [Double], higherIsBetter: Bool?) -> some View {
        let base = BodyMetrics.baseline(history)
        let delta: Double? = if let value, let base, base.mean > 0 { (value - base.mean) / base.mean * 100 } else { nil }
        return HStack {
            Text(name).font(.system(size: 13)).foregroundStyle(W.muted)
            Spacer()
            if let delta, abs(delta) >= 1 {
                let good = higherIsBetter.map { $0 == (delta > 0) }
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(good == nil ? W.muted : good! ? W.green : W.red)
                Text("\(Int(abs(delta)))%").font(.system(size: 11)).foregroundStyle(W.muted)
            }
            Text(value.map { unit == "h" ? Self.hm($0) : "\(Int($0.rounded())) \(unit)" } ?? "–")
                .font(W.score(17)).foregroundStyle(W.text)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    // MARK: Sleep card

    private var sleepCard: some View {
        DarkCard {
            CardTitle("Sleep", "vs need") { pillar = .sleep }
            HStack(alignment: .firstTextBaseline) {
                Text(scores.day.sleepH.map(Self.hm) ?? "–").font(W.score(34)).foregroundStyle(W.text)
                Text("of \(Self.hm(scores.sleepNeed.total)) needed")
                    .font(.system(size: 13)).foregroundStyle(W.muted)
                Spacer()
            }
            .padding(.bottom, 8)
            SleepStageBar(day: scores.day)
            HStack(spacing: 14) {
                if let e = scores.day.efficiency {
                    sleepChip("EFFICIENCY", "\(Int(e))%")
                }
                if let c = BodyMetrics.consistencyMinutes(bedTimes: store.recentBedTimes()) {
                    sleepChip("CONSISTENCY", "±\(c) min")
                }
                if let a = scores.day.awakeCount, a > 0 {
                    sleepChip("DISTURBANCES", "\(a)")
                }
                if let nap = scores.day.napH, nap > 0 {
                    sleepChip("NAP", Self.hm(nap))
                }
                Spacer()
            }
            .padding(.top, 10)
            DividedRows(topPadding: 10, rows: needRows)
            if dayOffset == 0 { logNapButton }
        }
        .onTapGesture { pillar = .sleep }
    }

    private var logNapButton: some View {
        Menu {
            ForEach([15, 20, 30, 45, 60, 90], id: \.self) { m in
                Button("\(m) min") { Task { await health.logNap(minutes: m, store: store) } }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.system(size: 13))
                Text("Log a nap").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(W.blue).padding(.top, 10)
        }
    }

    private func sleepChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(W.label(8)).kerning(0.5).foregroundStyle(W.muted)
            Text(value).font(W.score(14)).foregroundStyle(W.text)
        }
    }

    private var needRows: [AnyView] {
        var rows: [AnyView] = [AnyView(needRow("Baseline", scores.sleepNeed.baseline))]
        if scores.sleepNeed.debt > 0.01 { rows.append(AnyView(needRow("+ Sleep debt", scores.sleepNeed.debt))) }
        if scores.sleepNeed.strainCredit > 0 { rows.append(AnyView(needRow("+ Yesterday's strain", scores.sleepNeed.strainCredit))) }
        if scores.sleepNeed.napCredit > 0 { rows.append(AnyView(needRow("− Nap credit", scores.sleepNeed.napCredit))) }
        rows.append(AnyView(needRow("Sleep need", scores.sleepNeed.total, bold: true)))
        return rows
    }

    private func needRow(_ label: String, _ hours: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: bold ? .bold : .regular))
                .foregroundStyle(bold ? W.text : W.muted)
            Spacer()
            Text(Self.hm(hours)).font(bold ? W.score(14) : .system(size: 12))
                .foregroundStyle(bold ? W.text : W.muted)
        }
        .padding(.vertical, 7)
    }

    // MARK: Strain card

    private var strainCard: some View {
        DarkCard {
            CardTitle("Strain", scores.strain.score > 0 ? scores.strain.label : "No activity yet") { pillar = .strain }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", scores.strain.score)).font(W.score(34)).foregroundStyle(W.blue)
                Text("/ 21").font(.system(size: 13)).foregroundStyle(W.muted)
                Spacer()
                if let r = scores.recovery {
                    let t = BodyMetrics.targetStrain(recovery: r.score)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("TARGET").font(W.label(9)).kerning(1).foregroundStyle(W.muted)
                        Text("\(String(format: "%.1f", t.lowerBound))–\(String(format: "%.1f", t.upperBound))")
                            .font(W.score(17)).foregroundStyle(W.recoveryColor(r.zone))
                    }
                }
            }
            StrainTargetBar(strain: scores.strain.score, recovery: scores.recovery)
                .padding(.top, 8)
            HStack(spacing: 0) {
                statCell("Active kcal", scores.health?.activeKcal.map { "\(Int($0))" } ?? "–")
                statCell("Steps", (scores.health?.steps).map { $0.formatted() } ?? "–")
                statCell("Total burn", scores.health?.burnedKcal.map { "\(Int($0))" } ?? "–")
            }
            .padding(.top, 12)
            workloadRow
            if !scores.workouts.isEmpty {
                DividedRows(topPadding: 8, rows: scores.workouts.map { w in AnyView(workoutRow(w)) })
            }
        }
        .onTapGesture { pillar = .strain }
    }

    private func workloadColor(_ zone: BodyMetrics.Workload.Zone) -> Color {
        switch zone {
        case .detraining: W.sleep
        case .sweetSpot: W.green
        case .high: W.yellow
        case .danger: W.red
        }
    }

    /// Acute:chronic workload ratio — 7-day load vs 28-day, with a sweet-spot band (0.8–1.3).
    @ViewBuilder private var workloadRow: some View {
        if let wl = scores.workload {
            VStack(spacing: 6) {
                Rectangle().fill(W.divider).frame(height: 1).padding(.top, 10)
                HStack(alignment: .firstTextBaseline) {
                    Text("TRAINING LOAD").font(W.label(10)).kerning(1).foregroundStyle(W.muted)
                    Spacer()
                    Text(wl.label).font(.system(size: 11)).foregroundStyle(workloadColor(wl.zone))
                }
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", wl.ratio)).font(W.score(24)).foregroundStyle(workloadColor(wl.zone))
                    Text("acute : chronic").font(.system(size: 11)).foregroundStyle(W.muted)
                    Spacer()
                    Text("7d \(Int(wl.acute.rounded())) · 28d \(Int(wl.chronic.rounded()))")
                        .font(.system(size: 11)).foregroundStyle(W.muted)
                }
                // ratio scale 0–2 with the 0.8–1.3 sweet-spot band highlighted
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(W.card2)
                        Capsule().fill(W.green.opacity(0.25))
                            .frame(width: geo.size.width * (1.3 - 0.8) / 2.0)
                            .offset(x: geo.size.width * 0.8 / 2.0)
                        Circle().fill(workloadColor(wl.zone)).frame(width: 12, height: 12)
                            .offset(x: min(geo.size.width - 12, max(0, geo.size.width * min(wl.ratio, 2) / 2.0 - 6)))
                    }
                }
                .frame(height: 12)
            }
        }
    }

    private func workoutRow(_ w: WorkoutEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run").font(.system(size: 12)).foregroundStyle(W.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(w.name).font(W.label(13)).foregroundStyle(W.text)
                Text("\(Int(w.minutes)) min" + (w.avgHR.map { " · \(Int($0)) bpm avg" } ?? "")
                     + (w.kcal.map { " · \(Int($0)) kcal" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(W.muted)
            }
            Spacer()
            Text(String(format: "%.1f",
                        BodyMetrics.workoutStrain(w, capKcal: scores.capKcal, capTrimp: scores.capTrimp)))
                .font(W.score(17)).foregroundStyle(W.blue)
        }
        .padding(.vertical, 8)
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(W.score(17)).foregroundStyle(W.text)
            Text(label.uppercased()).font(W.label(9)).kerning(0.5).foregroundStyle(W.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Vitals monitor

    private var vitalsCard: some View {
        DarkCard {
            CardTitle("Health Monitor", "vs your typical range", chevron: false) {}
            DividedRows(rows: monitorRows)
        }
    }

    // HRV / resting HR / respiratory rate / sleep live on the Recovery card (their home);
    // the Health Monitor owns the remaining vitals so nothing is listed twice.
    private var monitorRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(monitorRow("Wrist temp", scores.day.tempC, "°C", store.bodyHistory(\.tempC))),
            AnyView(monitorRow("Blood oxygen", scores.day.spo2, "%", store.bodyHistory(\.spo2))),
        ]
        if scores.health?.hrrBpm != nil {   // higher HRR = fitter, so a low reading is the concern
            rows.append(AnyView(monitorRow("HR recovery (1 min)", scores.health?.hrrBpm, "bpm",
                                           store.healthHistory(\.hrrBpm))))
        }
        // Optional metabolic/cardio rows — only appear once a source (CGM, BP cuff) writes to Health.
        if scores.health?.glucoseMgDl != nil {
            rows.append(AnyView(monitorRow("Blood glucose", scores.health?.glucoseMgDl, "mg/dL",
                                           store.healthHistory(\.glucoseMgDl))))
        }
        if let sys = scores.health?.bpSystolic, let dia = scores.health?.bpDiastolic {
            rows.append(AnyView(bpRow(sys: sys, dia: dia)))
        }
        return rows
    }

    /// Blood pressure shown as systolic/diastolic with a simple normal/elevated dot (≤120/80 normal).
    private func bpRow(sys: Double, dia: Double) -> some View {
        let normal = sys <= 120 && dia <= 80
        return HStack {
            Circle().fill(normal ? W.green : sys <= 130 ? W.yellow : W.red).frame(width: 8, height: 8)
            Text("Blood pressure").font(.system(size: 13)).foregroundStyle(W.text)
            Spacer()
            Text("normal ≤120/80").font(.system(size: 11)).foregroundStyle(W.muted)
            Text("\(Int(sys.rounded()))/\(Int(dia.rounded()))")
                .font(W.score(17)).foregroundStyle(W.text).frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private func monitorRow(_ name: String, _ value: Double?, _ unit: String, _ history: [Double]) -> some View {
        let range = BodyMetrics.typicalRange(history)
        let inRange = if let value, let range { range.contains(value) } else { true }
        func fmt(_ v: Double) -> String {
            switch unit {
            case "h": Self.hm(v)
            case "°C": String(format: "%.1f", v)
            default: "\(Int(v.rounded()))"
            }
        }
        return HStack {
            Circle().fill(value == nil || range == nil ? W.muted : inRange ? W.green : W.red)
                .frame(width: 8, height: 8)
            Text(name).font(.system(size: 13)).foregroundStyle(W.text)
            Spacer()
            if let range {
                Text("\(fmt(range.low))–\(fmt(range.high)) \(unit == "h" ? "" : unit)")
                    .font(.system(size: 11)).foregroundStyle(W.muted)
            } else {
                Text(value == nil ? "no data" : "calibrating").font(.system(size: 11)).foregroundStyle(W.muted)
            }
            Text(value.map(fmt) ?? "–")
                .font(W.score(17)).foregroundStyle(W.text)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    // MARK: Body composition (Hume-style, from a BIA scale via Apple Health)

    private var bodyCompositionCard: some View {
        let comp = store.bodyComposition()
        return DarkCard {
            CardTitle("Body Composition", comp != nil ? "body fat + lean mass" : "weight-based", chevron: false) {}
            HStack(spacing: 0) {
                statCell("Weight", store.currentWeight.map { String(format: "%.1f kg", $0) } ?? "–")
                statCell("Body fat", comp.map { String(format: "%.1f%%", $0.bodyFatPct) } ?? "–")
                statCell("BMI", store.bmi.map { String(format: "%.1f", $0) } ?? "–")
                statCell("BMR", store.bmr.map { "\($0)" } ?? "–")
            }
            if let c = comp {
                fatLeanBar(fatMass: c.fatMassKg, leanMass: c.leanMassKg)
                    .padding(.top, 12)
                HStack(spacing: 14) {
                    legend(String(format: "Fat %.1f kg", c.fatMassKg), W.yellow)
                    legend(String(format: "Lean %.1f kg", c.leanMassKg), W.vibrant)
                    Spacer()
                }
                .padding(.top, 8)
            } else {
                Text("Body fat and lean mass appear once a BIA band (wrist impedance) writes to Apple Health. Weight, BMI and BMR show from your logs today.")
                    .font(.system(size: 11)).foregroundStyle(W.muted).padding(.top, 8)
            }
            fitnessAgeRow
        }
    }

    @ViewBuilder private var fitnessAgeRow: some View {
        if let fa = store.fitnessAge() {
            let younger = fa.delta <= 0
            Rectangle().fill(W.divider).frame(height: 1).padding(.vertical, 12)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FITNESS AGE").font(W.label(9)).kerning(0.8).foregroundStyle(W.muted)
                    Text("\(Int(fa.age.rounded()))")
                        .font(W.score(34)).foregroundStyle(younger ? W.green : W.yellow)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(younger ? "\(Int(-fa.delta.rounded())) yrs younger" : "\(Int(fa.delta.rounded())) yrs older")
                        .font(W.score(15)).foregroundStyle(younger ? W.green : W.yellow)
                    Text("actual age \(fa.chronological)").font(.system(size: 11)).foregroundStyle(W.muted)
                }
            }
            if let top = fa.contributors.first {
                Text(top.offsetYears <= 0
                     ? "\(top.name) is keeping you youngest"
                     : "\(top.name) is aging you most — your biggest lever")
                    .font(.system(size: 11)).foregroundStyle(W.muted).padding(.top, 6)
            }
            Text("Estimate from your fitness metrics — not a clinical biological age.")
                .font(.system(size: 10)).foregroundStyle(W.muted.opacity(0.7)).padding(.top, 4)
        }
    }

    private func fatLeanBar(fatMass: Double, leanMass: Double) -> some View {
        let total = max(fatMass + leanMass, 0.01)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle().fill(W.yellow).frame(width: geo.size.width * fatMass / total)
                Rectangle().fill(W.vibrant)
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10)).foregroundStyle(W.muted)
        }
    }

    // MARK: Behavior impacts

    private var impactsCard: some View {
        DarkCard {
            CardTitle("Recovery Impacts", "next-day effect of your habits", chevron: false) {}
            if impacts.isEmpty {
                Text("Log habits for a few weeks to see which ones move your recovery.")
                    .font(.system(size: 12)).foregroundStyle(W.muted).padding(.vertical, 6)
            } else {
                DividedRows(rows: impacts.prefix(5).map { i in AnyView(impactRow(i)) })
            }
        }
    }

    private func impactRow(_ i: BehaviorImpact) -> some View {
        HStack {
            Image(systemName: i.delta >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(i.delta >= 0 ? W.green : W.red)
            Text(i.name).font(.system(size: 13)).foregroundStyle(W.text)
            Spacer()
            Text("\(i.delta >= 0 ? "+" : "")\(Int(i.delta.rounded())) %")
                .font(W.score(17)).foregroundStyle(i.delta >= 0 ? W.green : W.red)
        }
        .padding(.vertical, 8)
    }

    // MARK: Week in review

    private var weekReportCard: some View {
        DarkCard {
            CardTitle("Week in Review", "last 7 days", chevron: false) {}
            if let w = week {
                HStack(spacing: 0) {
                    statCell("Recovery", w.avgRecovery.map { "\($0)%" } ?? "–")
                    statCell("Strain", w.avgStrain.map { String(format: "%.1f", $0) } ?? "–")
                    statCell("Sleep", w.avgSleep.map(Self.hm) ?? "–")
                }
                HStack(spacing: 0) {
                    statCell("Sleep debt", Self.hm(w.sleepDebt))
                    statCell("Avg deficit", w.avgDeficit.map { "\(Int($0)) kcal" } ?? "–")
                    statCell("Weight", w.weightDelta.map { String(format: "%+.1f kg", $0) } ?? "–")
                }
                .padding(.top, 10)
            }
        }
    }

    static func hm(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }
}

// MARK: - Shared dark components

struct DarkCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(W.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Uppercased card header with a subtitle and (optionally) a chevron that signals the deep-dive.
struct CardTitle: View {
    let title: String
    let sub: String
    var chevron = true
    let action: () -> Void

    init(_ title: String, _ sub: String, chevron: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.sub = sub; self.chevron = chevron; self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased()).font(W.label(12)).kerning(1.2).foregroundStyle(W.muted)
            Spacer()
            Text(sub).font(.system(size: 11)).foregroundStyle(W.muted)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(W.muted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .padding(.bottom, 6)
    }
}

/// VStack whose children are separated by hairline dividers (array-based: iOS 17 has no subview reader).
struct DividedRows: View {
    var topPadding: CGFloat = 0
    let rows: [AnyView]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(W.divider).frame(height: 1) }
                rows[i]
            }
        }
        .padding(.top, topPadding)
    }
}

struct SleepStageBar: View {
    let day: RecoveryDay
    var body: some View {
        let total = max(day.sleepH ?? 0, 0.01)
        let deep = day.deepH ?? 0, rem = day.remH ?? 0
        let light = max(0, total - deep - rem)
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(W.blue).frame(width: geo.size.width * deep / total)
                    Rectangle().fill(W.vibrant).frame(width: geo.size.width * rem / total)
                    Rectangle().fill(W.sleep.opacity(0.55))
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                legend("Deep \(BodyView.hm(deep))", W.blue)
                legend("REM \(BodyView.hm(rem))", W.vibrant)
                legend("Light \(BodyView.hm(light))", W.sleep.opacity(0.55))
                Spacer()
            }
        }
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10)).foregroundStyle(W.muted)
        }
    }
}

struct StrainTargetBar: View {
    let strain: Double
    let recovery: BodyMetrics.Recovery?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(W.card2)
                if let r = recovery {
                    let t = BodyMetrics.targetStrain(recovery: r.score)
                    Capsule().fill(W.recoveryColor(r.zone).opacity(0.25))
                        .frame(width: geo.size.width * (t.upperBound - t.lowerBound) / 21)
                        .offset(x: geo.size.width * t.lowerBound / 21)
                }
                Capsule().fill(W.blue)
                    .frame(width: max(6, geo.size.width * strain / 21))
            }
        }
        .frame(height: 10)
    }
}

/// 270° arc gauge with rounded caps — the score sits inside, the label under it.
struct RingGauge: View {
    let title: String
    let value: String
    let fraction: Double        // 0...1
    let color: Color
    var size: CGFloat = 100
    var valueSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                arc(1).stroke(W.card, style: stroke)
                arc(max(0.02, min(1, fraction)))
                    .stroke(color, style: stroke)
                    .animation(.easeOut(duration: 0.6), value: fraction)
                Text(value).font(W.score(valueSize)).foregroundStyle(W.text)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 14)
            }
            .frame(width: size, height: size)
            Text(title.uppercased()).font(W.label()).kerning(1.2).foregroundStyle(W.muted)
        }
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: size * 0.085, lineCap: .round) }

    private func arc(_ f: Double) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: size / 2, y: size / 2),
                     radius: size / 2 - size * 0.05,
                     startAngle: .degrees(135),
                     endAngle: .degrees(135 + 270 * f),
                     clockwise: false)
        }
    }
}
