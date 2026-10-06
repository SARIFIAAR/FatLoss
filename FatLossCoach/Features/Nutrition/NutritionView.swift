import SwiftUI
import PhotosUI

/// Shared photo → analysis → log flow, driven by the scan card and by each meal-plan row.
@Observable
final class ScanFlow {
    var day: String = DateKey.key()        // the day being logged (selected in the week calendar)
    var slot: String?                      // meal key the photo belongs to (nil = other)
    var showCamera = false
    var showLibrary = false
    var pickerItem: PhotosPickerItem?
    var pending: PendingMeal?
    var error: String?
    var showTyped = false                  // FoodEntrySheet (database search / barcode / AI text)
    var typedStartsWithBarcode = false
    var showVoice = false                  // spoken meal description → AI text analysis
    var showAIChat = false                 // unified multimodal AI composer (text/voice/photo)
    var fromAIChat = false                 // the pending result came via the AI composer
    var showCompare = false                // barcode compare (two products)
    var showHub = false                    // "+ More ways to log" hub sheet
    var showQuickAdd = false               // quick-add calories sheet
    var hubTab: LogHubTab = .methods       // which hub tab opened last

    // Resilience: a single flow-owned analyzing flag drives the full-screen "Analyzing…" overlay
    // over the Nutrition screen (the composer dismisses immediately, so the indicator must live
    // here, not inside a card that may not even be on screen). It is set true before the /analyze
    // await and always cleared on completion or failure (defer), so the "+" / composer can never
    // be left in a stuck state.
    var isAnalyzing = false
    // The last input, kept so the error surface can offer a Retry that re-sends the SAME meal.
    var lastInput: PendingInput?

    /// What was submitted, so a failed analysis can be retried verbatim.
    enum PendingInput {
        case image(UIImage, slot: String?, fromAIChat: Bool)
        case text(String, slot: String?, fromAIChat: Bool)
    }

    struct PendingMeal: Identifiable {
        let id = UUID()
        let image: UIImage?                // nil when estimated from a written description
        let analysis: MealScanner.Analysis
        let slot: String?
    }

    func camera(slot: String?) { self.slot = slot; error = nil; showCamera = true }
    func typed(slot: String?, barcode: Bool = false) { self.slot = slot; error = nil; typedStartsWithBarcode = barcode; showTyped = true }
}

struct NutritionView: View {
    @Environment(Store.self) private var store
    @Environment(MealScanner.self) private var scanner
    @State private var flow = ScanFlow()
    // Debug / screenshots: `-nutritionDay 2026-09-06` opens the tab on that day.
    @State private var selectedDay = UserDefaults.standard.string(forKey: "nutritionDay") ?? DateKey.key()
    @State private var section: NutritionSection = {
        switch UserDefaults.standard.string(forKey: "nutritionSection") {
        case "program": return .program
        case "recipes": return .recipes
        default: return .diary
        }
    }()

    var body: some View {
        @Bindable var flow = flow
        let g = store.data.goals
        let ml = store.waterToday
        let pct = min(Double(ml) / Double(g.waterGoal), 1)
        let isToday = selectedDay == store.today
        Screen(subtitle: "Fuel your fat loss", title: "Nutrition") {
            SegmentedTabs(selection: $section,
                          options: NutritionSection.allCases.map { ($0, $0.rawValue) })
            switch section {
            case .program: ProgramSection()
            case .recipes: RecipesSection()
            case .diary: diaryContent(g: g, ml: ml, pct: pct, isToday: isToday, flow: flow)
            }
        }
        .fullScreenCover(isPresented: $flow.showCamera) {
            CameraPicker { image in
                flow.showCamera = false
                if let image { Task { await analyze(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: flow.pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await analyze(img)
                }
                flow.pickerItem = nil
            }
        }
        .sheet(item: $flow.pending) { p in
            MealResultSheet(image: p.image, analysis: p.analysis, slot: p.slot, date: flow.day,
                            onAdjust: { fix in flow.pending = nil; flow.fromAIChat = true; Task { await analyze(text: fix) } }) { entry in
                store.addMeal(entry)
                if flow.fromAIChat { store.noteAILog(); flow.fromAIChat = false }
                flow.pending = nil
            }
        }
        .sheet(isPresented: $flow.showTyped) {
            FoodEntrySheet(slot: flow.slot, date: flow.day, startWithBarcode: flow.typedStartsWithBarcode) { entry in
                store.addMeal(entry)
                flow.showTyped = false
            } onAIEstimate: { text in
                flow.showTyped = false
                Task { await analyze(text: text) }
            }
        }
        .sheet(isPresented: $flow.showVoice) {
            VoiceMealSheet { text in Task { await analyze(text: text) } }
        }
        .sheet(isPresented: $flow.showAIChat) {
            AIMealComposer(onText: { text in flow.fromAIChat = true; Task { await analyze(text: text) } },
                           onImage: { img in flow.fromAIChat = true; Task { await analyze(img) } },
                           onBarcode: { food in
                               // A scanned barcode becomes an editable estimate on the SAME result
                               // surface as text/voice/photo (portion picker, confidence, adjust).
                               flow.fromAIChat = true
                               flow.pending = ScanFlow.PendingMeal(image: nil,
                                                                   analysis: MealScanner.Analysis.fromBarcode(food),
                                                                   slot: flow.slot)
                           })
        }
        .sheet(isPresented: $flow.showCompare) { BarcodeCompareView() }
        .sheet(isPresented: $flow.showHub) { LogHubSheet(flow: flow, day: selectedDay) }
        .sheet(isPresented: $flow.showQuickAdd) { QuickAddSheet(flow: flow, day: selectedDay) }
        // Resilience overlays: the composer dismisses immediately, so progress and errors are shown
        // over the whole Nutrition screen — the user always sees state, never a blank/frozen screen.
        .overlay {
            if flow.isAnalyzing { AnalyzingOverlay() }
        }
        .overlay(alignment: .bottom) {
            if let error = flow.error, !flow.isAnalyzing {
                ScanErrorBanner(message: error,
                                canRetry: flow.lastInput != nil,
                                onRetry: { Task { await retry() } },
                                onDismiss: { flow.error = nil; flow.fromAIChat = false; flow.lastInput = nil })
                    .padding(.horizontal, 16).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.isAnalyzing)
        .animation(.easeInOut(duration: 0.2), value: flow.error)
        .onAppear {
            // Debug / screenshots: `-nutritionHub methods|recents|favorites|yesterday` opens the "+"
            // hub; `-nutritionQuickAdd 1` opens quick-add; both scoped by `-nutritionSlot <key>`.
            if let raw = UserDefaults.standard.string(forKey: "nutritionHub"),
               let t = LogHubTab.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) {
                flow.slot = UserDefaults.standard.string(forKey: "nutritionSlot")
                flow.hubTab = t
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flow.showHub = true }
            } else if UserDefaults.standard.string(forKey: "nutritionQuickAdd") != nil {
                flow.slot = UserDefaults.standard.string(forKey: "nutritionSlot")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flow.showQuickAdd = true }
            } else if UserDefaults.standard.string(forKey: "nutritionCompose") != nil {
                // Screenshot aid: open the "Log with AI" composer (shows the inline barcode input).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flow.showAIChat = true }
            } else if UserDefaults.standard.string(forKey: "nutritionBarcodeResult") != nil {
                // Screenshot aid: present the result surface a scanned barcode feeds — the same
                // MealResultSheet (portion picker, confidence, editable estimate) the composer routes to.
                let demo = FoodSearch.Food(id: "demo", name: "Greek Yoghurt (0% fat)", brand: "Fage",
                    kind: "branded", category: "Dairy",
                    per100: FoodSearch.Macros(kcal: 57, protein: 10, carbs: 4, fat: 0,
                                              fibre: 0, sugar: 4, sodium: 36, satFat: 0),
                    servings: [], barcode: "5201054001234")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    flow.fromAIChat = true
                    flow.pending = ScanFlow.PendingMeal(image: nil,
                                                        analysis: MealScanner.Analysis.fromBarcode(demo),
                                                        slot: "breakfast")
                }
            } else if UserDefaults.standard.string(forKey: "nutritionAnalyzing") != nil {
                // Screenshot / QA aid: show the "Analyzing your meal…" resilience overlay.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flow.isAnalyzing = true }
            } else if UserDefaults.standard.string(forKey: "nutritionScanError") != nil {
                // Screenshot / QA aid: show the error + Retry surface (as after a timeout).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    flow.lastInput = .text("2 eggs, toast and a flat white", slot: nil, fromAIChat: true)
                    flow.error = MealScanner.ScanError.timedOut.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func diaryContent(g: Goals, ml: Int, pct: Double, isToday: Bool, flow: ScanFlow) -> some View {
        @Bindable var flow = flow
        AINudgeBanner { flow.slot = nil; flow.error = nil; flow.showAIChat = true }
        ActivePlanBanner()
        FastingCard()
        DiarySummaryCard(day: selectedDay)
        // Screenshot aid (`-nutritionShots 1`): surface the eaten-meals card (with per-meal ratings)
        // right under the day summary so item/meal/day ratings are all visible without scrolling.
        if UserDefaults.standard.string(forKey: "nutritionShots") != nil {
            TodayMealsCard(day: selectedDay)
        }
        WeekCalendarCard(selected: $selectedDay)
            .onAppear { flow.day = selectedDay }
            .onChange(of: selectedDay) { _, d in flow.day = d }
        // Diary-first: the meal plan and its per-slot logging sit right under the calendar so
        // the plan is above the fold. Each meal-plan slot's own "+" menu (Log with AI / Same as
        // yesterday / Recent / Quick add) is the logging entry — no standalone "Log a meal" box.
        MealPlanCard(flow: flow, day: selectedDay)
        TodayMealsCard(day: selectedDay)
        Group {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                if Calendar.current.component(.hour, from: ctx.date) >= Plan.kitchenClosesHour {
                    HStack(spacing: 10) {
                        Text("")
                        Text("Kitchen is closed! Drink water or herbal tea instead.")
                    }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0xA0C4FF))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .background(Color(hex: 0x1A1A2E))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Card {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.blue.opacity(0.18)).frame(width: 36, height: 36)
                        Image(systemName: "drop.fill").font(.system(size: 15)).foregroundStyle(Theme.blue)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Water").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                        Text("\(ml) / \(g.waterGoal.formatted()) ml").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { store.addWater(250) } label: {
                        Text("+250").font(.system(size: 13, weight: .bold))
                    }.buttonStyle(PillButtonStyle())
                    Button { store.addWater(500) } label: {
                        Text("+500").font(.system(size: 13, weight: .bold))
                    }.buttonStyle(PillButtonStyle())
                }
                ProgressBar(value: pct, height: 8,
                            fill: AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.blue], startPoint: .leading, endPoint: .trailing)))
                    .padding(.top, 8)
            }

        }
    }

    private func context() -> MealScanner.Context {
        let g = store.data.goals
        return MealScanner.Context(kcalTarget: g.kcal, proteinTarget: g.protein, currentWeightKg: store.currentWeight,
                                   goalWeightKg: g.goalWeight, slot: flow.slot)
    }

    private func analyze(text: String) async {
        // Double-submit guard: rapid taps (or a retry while one is running) can't stack requests.
        guard !flow.isAnalyzing else { return }
        let slot = flow.slot
        let fromAIChat = flow.fromAIChat
        flow.lastInput = .text(text, slot: slot, fromAIChat: fromAIChat)
        flow.error = nil
        flow.isAnalyzing = true
        defer { flow.isAnalyzing = false }   // always clears — success, failure or timeout.
        do {
            let hint = Plan.meal(slot).map { "This is my \($0.name.dropFirst(2))." }
            let a = try await scanner.analyze(text: text, hint: hint, context: context())
            flow.fromAIChat = fromAIChat
            flow.pending = ScanFlow.PendingMeal(image: nil, analysis: a, slot: slot)
        } catch {
            flow.error = error.localizedDescription
        }
    }

    private func analyze(_ image: UIImage) async {
        guard !flow.isAnalyzing else { return }
        let slot = flow.slot
        let fromAIChat = flow.fromAIChat
        flow.lastInput = .image(image, slot: slot, fromAIChat: fromAIChat)
        flow.error = nil
        flow.isAnalyzing = true
        defer { flow.isAnalyzing = false }
        do {
            let hint = Plan.meal(slot).map { "This is my \($0.name.dropFirst(2))." }
            let a = try await scanner.analyze(image, hint: hint, context: context())
            flow.fromAIChat = fromAIChat
            flow.pending = ScanFlow.PendingMeal(image: image, analysis: a, slot: slot)
        } catch {
            flow.error = error.localizedDescription
        }
    }

    /// Re-send the last submitted meal verbatim. Called from the error surface's Retry.
    private func retry() async {
        guard !flow.isAnalyzing, let input = flow.lastInput else { return }
        switch input {
        case let .image(img, slot, fromAIChat):
            flow.slot = slot; flow.fromAIChat = fromAIChat
            await analyze(img)
        case let .text(t, slot, fromAIChat):
            flow.slot = slot; flow.fromAIChat = fromAIChat
            await analyze(text: t)
        }
    }
}

/// Full-screen "Analyzing your meal…" overlay shown while an AI /analyze request is in flight.
/// The composer dismisses immediately after handing off the photo/text, so this is what the user
/// sees during the ~9 s (warm) analysis — clear progress, never a blank or frozen screen.
struct AnalyzingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.primary)
                VStack(spacing: 4) {
                    Text("Analyzing your meal…")
                        .font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("Estimating calories and macros. This usually takes a few seconds.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .padding(32)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing your meal")
    }
}

/// Dismissible error surface for a failed/timed-out analysis, with a Retry that re-sends the same
/// meal. Sits at the bottom of the Nutrition screen so it's visible no matter which entry point ran.
struct ScanErrorBanner: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16)).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if canRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry").font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.red.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

struct WaveView: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0xE8F7FF), Color(hex: 0xCCE8F7)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Theme.accent, Theme.blue], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * max(0, min(1, fraction)))
                    .animation(.easeOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: 72)
        .clipShape(Capsule())
    }
}

struct MacroBar: View {
    let name: String
    let value: String
    let fraction: Double
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(name).foregroundStyle(Theme.text)
                Spacer()
                Text(value).fontWeight(.heavy).foregroundStyle(color)
            }
            .font(.system(size: 13))
            ProgressBar(value: fraction, height: 10, fill: AnyShapeStyle(color))
        }
    }
}

// MARK: - Meal photo scanner

/// Compact diary logging card: one primary "Log with AI" action + a single "+ More ways to log"
/// button that opens the hub (all other methods, plus Recents / Favorites / Same as yesterday /
/// Quick add). Collapses the old 7-button stack so the diary and meal plan stay above the fold.
struct LogEntryCard: View {
    @Bindable var flow: ScanFlow
    @Environment(MealScanner.self) private var scanner
    @Environment(CloudSync.self) private var cloud

    var body: some View {
        Card {
            SectionTitle(flow.day == DateKey.key() ? "Log a meal" : "Log a meal · \(WeekCalendarCard.longDay(flow.day))")
            if !cloud.isSignedIn {
                Text("Sign in with Apple in the Profile tab to enable meal logging.")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                    .padding(.bottom, 8)
            }
            // Primary, AI-first entry (Lifesum-style unified logging).
            Button { flow.slot = nil; flow.error = nil; flow.showAIChat = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Log with AI").font(.system(size: 16, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!cloud.isSignedIn)
            .padding(.bottom, 10)
            // The hub holds every other logging method + recents/favorites/same-as-yesterday/quick add.
            Button { flow.slot = nil; flow.error = nil; flow.hubTab = .methods; flow.showHub = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                    Text("More ways to log").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!cloud.isSignedIn)
            if flow.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.primary)
                    Text("Working out the nutrition…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 10)
            }
            // Errors and Retry are surfaced by the screen-level ScanErrorBanner (single error surface),
            // so nothing is shown twice here.
        }
    }
}

/// Meal plan with a "+" per meal: photo, library, typed search or barcode — all logged against that meal slot.
struct MealPlanCard: View {
    @Bindable var flow: ScanFlow
    var day: String
    @Environment(Store.self) private var store
    @Environment(MealScanner.self) private var scanner
    @Environment(CloudSync.self) private var cloud

    var body: some View {
        Card {
            SectionTitle("Meal Plan")
            VStack(spacing: 0) {
                ForEach(Array(Plan.meals.enumerated()), id: \.element.id) { i, m in
                    let eaten = store.kcal(slot: m.key, on: day)
                    let logged = eaten > 0
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(m.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                if logged {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.primary)
                                }
                            }
                            Text(m.time).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if logged {
                                Text("\(Int(eaten.rounded())) kcal")
                                    .font(Theme.scoreS)
                                    .foregroundStyle(eaten > Double(m.targetKcal) * 1.25 ? Theme.red : Theme.primary)
                                Text("plan \(m.kcal)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                            } else {
                                Text(m.kcal).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                        }
                        Menu {
                            let yCount = store.yesterdayItems(slot: m.key, before: day).count
                            if yCount > 0 {
                                Button { flow.slot = m.key; flow.error = nil; flow.hubTab = .yesterday; flow.showHub = true } label: {
                                    Label("Same as yesterday (\(yCount))", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            Button { flow.slot = m.key; flow.error = nil; flow.hubTab = .recents; flow.showHub = true } label: { Label("Recent foods", systemImage: "arrow.counterclockwise") }
                            Button { flow.slot = m.key; flow.error = nil; flow.showQuickAdd = true } label: { Label("Quick add", systemImage: "bolt.fill") }
                            Divider()
                            Button { flow.camera(slot: m.key) } label: { Label("Take photo", systemImage: "camera.fill") }
                            Button { flow.slot = m.key; flow.error = nil; flow.showLibrary = true } label: { Label("Choose from library", systemImage: "photo.on.rectangle") }
                            Button { flow.typed(slot: m.key) } label: { Label("Type it in", systemImage: "keyboard") }
                            Button { flow.typed(slot: m.key, barcode: true) } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                            Button { flow.slot = m.key; flow.error = nil; flow.showAIChat = true } label: { Label("Log with AI", systemImage: "sparkles") }
                        } label: {
                            Image(systemName: logged ? "plus.circle" : "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(logged ? Theme.primaryLight : Theme.primary)
                                .clipShape(Circle())
                        }
                        .disabled(flow.isAnalyzing || !cloud.isSignedIn)
                    }
                    .padding(.vertical, 10)
                    if i < Plan.meals.count - 1 { Divider().overlay(Theme.border) }
                }
            }
            Text("Kitchen closes at 9:00 PM — no food after this")
                .font(.system(size: 12)).foregroundStyle(Theme.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 10)
        }
        .photosPicker(isPresented: $flow.showLibrary, selection: $flow.pickerItem, matching: .images, photoLibrary: .shared())
    }
}

/// UIImagePickerController camera wrapper (PhotosPicker covers the library).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.cameraCaptureMode = .photo
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

struct MealResultSheet: View {
    let image: UIImage?
    let analysis: MealScanner.Analysis
    let onAdd: (MealEntry) -> Void
    let onAdjust: ((String) -> Void)?
    let date: String
    @State private var slot: String?
    @State private var portion: Double = 1        // serving multiplier
    @State private var correction = ""
    @State private var showCorrection = false
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(image: UIImage?, analysis: MealScanner.Analysis, slot: String? = nil, date: String? = nil,
         onAdjust: ((String) -> Void)? = nil, onAdd: @escaping (MealEntry) -> Void) {
        self.image = image
        self.analysis = analysis
        self.onAdd = onAdd
        self.onAdjust = onAdjust
        self.date = date ?? DateKey.key()
        _slot = State(initialValue: slot)
    }

    private func s(_ v: Double) -> Double { v * portion }

    /// The analysis as a MealEntry at the currently-selected portion, so the meal-level rating badge
    /// tracks the portion picker. Items carry through so the distribution factor still applies.
    private var scaledEntry: MealEntry {
        var e = analysis.mealEntry(date: date)
        e.kcal = s(analysis.total_kcal); e.protein = s(analysis.total_protein_g)
        e.carbs = s(analysis.total_carbs_g); e.fat = s(analysis.total_fat_g)
        e.items = analysis.items.map { FoodItem(name: $0.name, portion: $0.portion, grams: $0.grams * portion,
                                                kcal: s($0.kcal), protein: s($0.protein_g),
                                                carbs: s($0.carbs_g), fat: s($0.fat_g)) }
        return e
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(height: 180).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        HStack(spacing: 8) {
                            Text("")
                            Text("Editable estimate — confirm or adjust before logging").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(alignment: .firstTextBaseline) {
                        // Meal-level plan-aware rating on the result screen (reflects the chosen portion).
                        if let mealRating = FoodRating.rate(meal: scaledEntry, planId: store.data.nutritionPlanId) {
                            RatingBadgeButton(rating: mealRating, size: 24, title: analysis.meal_name)
                                .padding(.trailing, 2)
                        }
                        Text(analysis.meal_name).font(Theme.scoreM).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(analysis.confidence.capitalized) confidence")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(analysis.confidence == "high" ? Theme.primary : Theme.orange)
                            .padding(.vertical, 3).padding(.horizontal, 8)
                            .background((analysis.confidence == "high" ? Theme.primary : Theme.orange).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        MacroStat(value: "\(Int(s(analysis.total_kcal).rounded()))", label: "kcal", color: Theme.primary)
                        MacroStat(value: "\(Int(s(analysis.total_protein_g).rounded()))g", label: "protein", color: Theme.primary)
                        MacroStat(value: "\(Int(s(analysis.total_carbs_g).rounded()))g", label: "carbs", color: Theme.orange)
                        MacroStat(value: "\(Int(s(analysis.total_fat_g).rounded()))g", label: "fat", color: Theme.blue)
                    }
                    .padding(.vertical, 12)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Portion multiplier
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PORTION").font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { p in
                                Button(p == 1 ? "1×" : (p == 0.5 ? "½×" : "\(p == 1.5 ? "1.5" : "2")×")) { portion = p }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(portion == p ? Color(hex: 0x101518) : Theme.text)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(portion == p ? Theme.primary : Theme.bg, in: Capsule())
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(analysis.items.enumerated()), id: \.offset) { i, it in
                            HStack {
                                // Item-level plan-aware rating per food row.
                                if let ir = FoodRating.rate(item: FoodItem(name: it.name, portion: it.portion, grams: it.grams,
                                                                           kcal: s(it.kcal), protein: s(it.protein_g),
                                                                           carbs: s(it.carbs_g), fat: s(it.fat_g)),
                                                            planId: store.data.nutritionPlanId) {
                                    RatingBadgeButton(rating: ir, size: 18, title: it.name).padding(.trailing, 2)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                    Text("\(it.portion) · P \(Int(s(it.protein_g).rounded())) · C \(Int(s(it.carbs_g).rounded())) · F \(Int(s(it.fat_g).rounded()))")
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("\(Int(s(it.kcal).rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                            }
                            .padding(.vertical, 9)
                            if i < analysis.items.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }

                    if !analysis.notes.isEmpty {
                        Text("ℹ \(analysis.notes)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                    }

                    // Natural-language correction turn
                    if onAdjust != nil {
                        if showCorrection {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("WHAT SHOULD I FIX?").font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                                TextField("e.g. it was skimmed milk, no sugar", text: $correction, axis: .vertical)
                                    .font(.system(size: 14)).foregroundStyle(Theme.text)
                                    .padding(12).background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Button("Re-estimate") {
                                    let fix = "The meal was \"\(analysis.meal_name)\". Correction: \(correction.trimmingCharacters(in: .whitespaces))."
                                    onAdjust?(fix); dismiss()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(correction.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else {
                            Button { showCorrection = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.left"); Text("Not quite? Adjust it")
                                }.font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.blue)
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                        }
                    }

                    SlotPicker(slot: $slot).padding(.top, 4)

                    Button(Plan.logLabel(slot)) {
                        var e = analysis.mealEntry(date: date)
                        if portion != 1 {
                            e.kcal *= portion; e.protein *= portion; e.carbs *= portion; e.fat *= portion
                            e.name = portion == 0.5 ? "½ \(e.name)" : "\(portion == 1.5 ? "1.5" : "2")× \(e.name)"
                        }
                        e.slot = slot
                        onAdd(e)
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 6)
                    Button("Discard") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
            }
            .background(Theme.card)
            .navigationTitle("Meal estimate")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}

struct TodayMealsCard: View {
    var day: String
    @Environment(Store.self) private var store

    var body: some View {
        let meals = store.meals(on: day)
        if !meals.isEmpty {
            Card {
                SectionTitle(day == store.today ? "Eaten today" : "Eaten \(WeekCalendarCard.longDay(day))")
                VStack(spacing: 0) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { i, m in
                        HStack {
                            if let rating = FoodRating.rate(meal: m, planId: store.data.nutritionPlanId) {
                                RatingBadgeButton(rating: rating, title: m.name).padding(.trailing, 4)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                Text("\(Plan.meal(m.slot).map { $0.name + " · " } ?? "")\(m.time.formatted(date: .omitted, time: .shortened)) · P \(Int(m.protein.rounded())) · C \(Int(m.carbs.rounded())) · F \(Int(m.fat.rounded()))")
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(Int(m.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                            Button { store.toggleFavorite(m) } label: {
                                Image(systemName: store.isFavorite(m) ? "heart.fill" : "heart")
                                    .font(.system(size: 13)).foregroundStyle(store.isFavorite(m) ? Theme.red : Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 6)
                            Button { store.repeatMeal(m, on: store.today, slot: m.slot) } label: {
                                Image(systemName: "arrow.counterclockwise").font(.system(size: 13)).foregroundStyle(Theme.primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 6)
                            Button(role: .destructive) { store.deleteMeal(m) } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                        .padding(.vertical, 9)
                        if i < meals.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
            }
        }
    }
}

/// Shown when the selected day has no meals yet — offers to copy the previous day's meals.
struct CopyYesterdayCard: View {
    var day: String
    @Environment(Store.self) private var store

    var body: some View {
        let prev = DateKey.key(DateKey.date(day).map { $0.addingTimeInterval(-86400) } ?? Date())
        let prevMeals = store.meals(on: prev)
        if store.meals(on: day).isEmpty && !prevMeals.isEmpty {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Same as yesterday?").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                        Text("Copy \(prevMeals.count) meal\(prevMeals.count == 1 ? "" : "s") from \(WeekCalendarCard.longDay(prev))").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Copy") { store.copyMeals(from: prev, to: day) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }
}
