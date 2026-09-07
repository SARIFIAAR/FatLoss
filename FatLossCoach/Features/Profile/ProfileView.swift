import SwiftUI
import AuthenticationServices
import UIKit

struct ProfileView: View {
    @Environment(Store.self) private var store
    @State private var weightText = ""
    @State private var editPlan = false

    var body: some View {
        Screen(subtitle: "Your health profile", title: "Profile ⚙️") {
            headerCard
            PlanQuestionnaireCard(edit: $editPlan)
            GoalsCard()
            CloudCard()
            HealthCard()
            RemindersCard()
            medsCard
            AutomationCard()
            ImportExportCard()
            Text("Fat Loss Coach \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .fullScreenCover(isPresented: $editPlan) {
            OnboardingView(existing: store.data.intake, canSkip: true) { store.applyIntake($0) }
        }
    }

    private var headerCard: some View {
        let g = store.data.goals
        let me = store.data.intake
        return Card {
            VStack(spacing: 12) {
                Text(me.map { $0.initial.isEmpty ? "?" : $0.initial } ?? "M")
                    .font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 72, height: 72).background(Theme.primary).clipShape(Circle())
                VStack(spacing: 2) {
                    Text(me.map { $0.name.isEmpty ? "Fat Loss Coach" : $0.name } ?? "Fat Loss Coach").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
                    Text(me.map { "\($0.sex.label) · \($0.age) yrs · \(Fmt.num($0.heightCm)) cm" } ?? "Male · 49 yrs · 189 cm").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatBox {
                    Text("\(Fmt.num(store.currentWeight ?? g.startWeight)) kg").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.primary)
                    Text("Current Weight").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatBox {
                    Text("\(Fmt.num(g.goalWeight)) kg").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.orange)
                    Text("Goal Weight").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatBox {
                    Text("\(g.kcal)").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.blue)
                    Text("kcal / day").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatBox {
                    Text("−\(g.deficit)").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.primaryLight)
                    Text("Daily Deficit").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 14)

            SectionTitle("Update Weight")
            HStack(spacing: 10) {
                NumField(placeholder: "kg", text: $weightText, decimal: true, width: nil)
                Button("Save") {
                    if let v = Fmt.parse(weightText), store.logWeight(v) { weightText = "" }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    private var medsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⚠️ Medications — Important").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.orange)
            Text("**Wellbutrin (Bupropion) 300mg** — Suppresses appetite, boosts dopamine. Do NOT go below 1,200 kcal/day.")
            Text("**Brintellix (Vortioxetine) 20mg** — Weight-neutral. No dietary restrictions.")
            Text("Consult your doctor before any major dietary changes.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .font(.system(size: 13)).foregroundStyle(Theme.text).lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.adaptive(light: 0xFFF8F0, dark: 0x2A1F14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.orange, lineWidth: 1.5))
    }
}

// MARK: - Goals

struct GoalsCard: View {
    @Environment(Store.self) private var store
    @State private var start = ""
    @State private var goal = ""
    @State private var waist = ""
    @State private var steps = ""
    @State private var water = ""

    var body: some View {
        Card {
            SectionTitle("🎯 Goals")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                LabeledField(label: "Start weight (kg)", text: $start)
                LabeledField(label: "Goal weight (kg)", text: $goal)
                LabeledField(label: "Waist target (cm)", text: $waist)
                LabeledField(label: "Steps goal", text: $steps, decimal: false)
                LabeledField(label: "Water goal (ml)", text: $water, decimal: false)
            }
            Button("Save Goals") {
                var g = store.data.goals
                if let v = Fmt.parse(start), v > 0 { g.startWeight = v }
                if let v = Fmt.parse(goal), v > 0 { g.goalWeight = v }
                if let v = Fmt.parse(waist), v > 0 { g.waistTarget = v }
                if let v = Fmt.parse(steps), v > 0 { g.stepsGoal = Int(v) }
                if let v = Fmt.parse(water), v > 0 { g.waterGoal = Int(v) }
                store.data.goals = g
                store.showToast("Goals saved ✓")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .padding(.top, 10)
        }
        .onAppear {
            let g = store.data.goals
            start = Fmt.num(g.startWeight); goal = Fmt.num(g.goalWeight); waist = Fmt.num(g.waistTarget)
            steps = String(g.stepsGoal); water = String(g.waterGoal)
        }
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var decimal = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.blue)
            NumField(placeholder: "", text: $text, decimal: decimal, width: nil)
        }
    }
}

// MARK: - Cloud

struct CloudCard: View {
    @Environment(CloudSync.self) private var cloud
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Card {
            SectionTitle("☁️ Cloud Backup & Sync")
            if !cloud.isConfigured {
                Text("Cloud sync isn't configured in this build.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else if cloud.isSignedIn {
                Text(cloud.email ?? "Signed in with Apple").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                Text(cloud.status).font(.system(size: 12)).foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button(cloud.isSyncing ? "Syncing…" : "Sync now") { cloud.syncNow() }
                        .buttonStyle(PillButtonStyle()).disabled(cloud.isSyncing)
                    Button("Sign out") { cloud.signOut() }.buttonStyle(PillButtonStyle(outlined: true))
                }
                .padding(.top, 10)
            } else {
                Text("Back up your data and keep it in sync across your iPhone and iPad.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.bottom, 10)
                SignInWithAppleButton(.signIn, onRequest: cloud.prepareAppleRequest, onCompletion: cloud.handleApple)
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 44)
            }
            if let e = cloud.lastError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.top, 8)
            }
        }
    }
}

// MARK: - Apple Health

struct HealthCard: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var health
    @State private var showManual = false
    @State private var steps = ""
    @State private var rhr = ""
    @State private var hrv = ""
    @State private var sleep = ""
    @State private var deep = ""
    @State private var rem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("⌚ Apple Watch — Health Sync").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.blue)
                .padding(.bottom, 8)
            Text(health.lastSync.map { "Last synced \($0.formatted(date: .abbreviated, time: .shortened))" }
                 ?? "Reads steps, resting HR, HRV, respiratory rate and sleep stages straight from Apple Health.")
                .font(.system(size: 12)).foregroundStyle(Theme.text).lineSpacing(3)
                .padding(.bottom, 10)
            Button(health.isSyncing ? "Syncing…" : (health.hasConnected ? "⌚ Sync now" : "⌚ Connect Apple Health")) {
                Task {
                    if health.hasConnected { await health.sync(store: store, days: 30) }
                    else { await health.connectAndSync(store: store, days: 30) }
                }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.blue))
            .disabled(health.isSyncing || !health.isAvailable)
            if let e = health.lastError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.top, 8)
            }

            DisclosureGroup(isExpanded: $showManual) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    LabeledField(label: "Steps", text: $steps, decimal: false)
                    LabeledField(label: "Resting HR (bpm)", text: $rhr, decimal: false)
                    LabeledField(label: "HRV (ms)", text: $hrv)
                    LabeledField(label: "Total Sleep (h)", text: $sleep)
                    LabeledField(label: "Deep Sleep (h)", text: $deep)
                    LabeledField(label: "REM Sleep (h)", text: $rem)
                }
                .padding(.top, 8)
                Button("Sync to Recovery Dashboard") {
                    store.manualSync(steps: Fmt.parse(steps).map { Int($0) }, rhr: Fmt.parse(rhr), hrv: Fmt.parse(hrv),
                                     sleep: Fmt.parse(sleep), deep: Fmt.parse(deep), rem: Fmt.parse(rem))
                    steps = ""; rhr = ""; hrv = ""; sleep = ""; deep = ""; rem = ""
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.blue, compact: true))
                .padding(.top, 10)
            } label: {
                Text("Enter manually").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.blue)
            }
            .tint(Theme.blue)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.adaptive(light: 0xF0F4FF, dark: 0x141C2E))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.blue, lineWidth: 1.5))
    }
}

// MARK: - Reminders (local notifications)

struct RemindersCard: View {
    @Environment(Store.self) private var store
    @Environment(ReminderManager.self) private var reminders

    private let intervals = [60, 90, 120, 180]
    private let hours = Array(6...23)

    var body: some View {
        Card {
            SectionTitle("🔔 Reminders")
            if reminders.permission == .denied {
                Text("Notifications are off for Fat Loss Coach in iOS Settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.red)
                Button("Open Settings") { reminders.openSystemSettings() }
                    .buttonStyle(PillButtonStyle(outlined: true)).padding(.bottom, 8)
            }

            Toggle(isOn: binding(\.waterOn)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("💧 Drink water").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Every \(intervalLabel(store.data.reminders.waterEveryMinutes)) between \(hourLabel(store.data.reminders.startHour)) and \(hourLabel(store.data.reminders.endHour)); stops once you hit \(store.data.goals.waterGoal.formatted()) ml. Tap a reminder to log a glass.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.primary)
            if store.data.reminders.waterOn {
                HStack(spacing: 8) {
                    picker("Every", selection: binding(\.waterEveryMinutes), options: intervals) { intervalLabel($0) }
                    picker("From", selection: binding(\.startHour), options: hours) { hourLabel($0) }
                    picker("Until", selection: binding(\.endHour), options: hours) { hourLabel($0) }
                }
                .padding(.top, 6)
            }

            Divider().padding(.vertical, 10)

            Toggle(isOn: binding(\.walkOn)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🚶 Go for a walk").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Step check-ins with how far you are from \(store.data.goals.stepsGoal.formatted()) steps; skipped once you're there.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.primary)
            if store.data.reminders.walkOn {
                HStack(spacing: 8) {
                    picker("1st nudge", selection: walkHour(0), options: hours) { hourLabel($0) }
                    picker("2nd nudge", selection: walkHour(1), options: [0] + hours) { $0 == 0 ? "none" : hourLabel($0) }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: helpers

    private func binding<T>(_ key: WritableKeyPath<ReminderSettings, T>) -> Binding<T> {
        Binding(get: { store.data.reminders[keyPath: key] },
                set: { v in
                    store.data.reminders[keyPath: key] = v
                    if (v as? Bool) == true { Task { await reminders.requestPermission(); reminders.schedulePlan() } }
                    else { reminders.schedulePlan() }
                })
    }

    private func walkHour(_ index: Int) -> Binding<Int> {
        Binding(get: { store.data.reminders.walkHours.count > index ? store.data.reminders.walkHours[index] : 0 },
                set: { v in
                    var h = store.data.reminders.walkHours
                    if index < h.count { h[index] = v } else { h.append(v) }
                    store.data.reminders.walkHours = Array(Set(h.filter { $0 > 0 })).sorted()
                    reminders.schedulePlan()
                })
    }

    @ViewBuilder
    private func picker<T: Hashable>(_ label: String, selection: Binding<T>, options: [T], text: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { Text(text($0)).tag($0) }
            }
            .pickerStyle(.menu).tint(Theme.primary)
            .labelsHidden()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func intervalLabel(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60) h" : "\(m / 60)½ h" }
    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))   // "9 AM", "21" in 24-h locales
    }
}

// MARK: - Shortcuts automation

struct AutomationCard: View {
    @Environment(Store.self) private var store
    private let template = "fatlosscoach://sync?hrv=[HRV]&rhr=[RHR]&sleep=[Sleep]&deep=[Deep]&rem=[REM]&resp=[Resp]&mood=[Mood]&steps=[Steps]"

    var body: some View {
        Card {
            SectionTitle("🤖 Shortcuts automation (optional)")
            Text("Apple Health sync above is automatic. If you also want a Shortcut (e.g. to push State of Mind), have it open this URL:")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
            Text(template)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0x7DD3FC))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(hex: 0x1E293B))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.vertical, 8)
            Button("Copy URL template") {
                UIPasteboard.general.string = template
                store.showToast("Copied ✓")
            }
            .buttonStyle(PillButtonStyle(color: Theme.blue))
        }
    }
}

// MARK: - Import / export

struct ImportExportCard: View {
    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var result: String?

    var body: some View {
        Card {
            SectionTitle("📥 Import from the web app")
            Text("In the old web app open Profile → “Copy my data”, then tap Paste and Import here. Existing entries are merged, nothing is deleted.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .padding(.bottom, 8)
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 90)
                .padding(6)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 2))
            HStack(spacing: 10) {
                Button("Paste") { text = UIPasteboard.general.string ?? "" }
                    .buttonStyle(PillButtonStyle(outlined: true))
                Button("Import") {
                    do {
                        let n = try store.importLegacy(text)
                        result = n > 0 ? "Imported \(n) records ✓" : "Nothing recognised in that text."
                        if n > 0 { text = "" }
                    } catch {
                        result = error.localizedDescription
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 10)
            if let result {
                Text(result).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 8)
            }
            Divider().overlay(Theme.border).padding(.vertical, 14)
            SectionTitle("📤 Export")
            ShareLink(item: store.exportJSON(), preview: SharePreview("Fat Loss Coach data")) {
                Label("Share data as JSON", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
            }
        }
    }
}


/// Entry point to the plan questionnaire (first-run onboarding, re-openable to tune the plan).
struct PlanQuestionnaireCard: View {
    @Binding var edit: Bool
    @Environment(Store.self) private var store

    var body: some View {
        Card {
            SectionTitle("📋 My plan")
            if let p = store.data.intake {
                Text("\(p.pace.label) pace · \(p.trainingDays) training days · \(p.location.label.lowercased()) · \(p.eatingStyle.label.lowercased()) · \(p.mealsPerDay) meals/day")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                if let d = p.completedAt {
                    Text("Answers saved \(d.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 2)
                }
                Button("Edit my answers") { edit = true }.buttonStyle(SecondaryButtonStyle()).padding(.top, 10)
            } else {
                Text("Answer nine short questions about your body, goal, training, food and lifestyle, and the calorie, protein, water and step targets are built for you.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                Button("Build my plan") { edit = true }.buttonStyle(PrimaryButtonStyle()).padding(.top, 10)
            }
        }
    }
}
