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
                           onImage: { img in flow.fromAIChat = true; Task { await analyze(img) } })
        }
        .sheet(isPresented: $flow.showCompare) { BarcodeCompareView() }
        .sheet(isPresented: $flow.showHub) { LogHubSheet(flow: flow, day: selectedDay) }
        .sheet(isPresented: $flow.showQuickAdd) { QuickAddSheet(flow: flow, day: selectedDay) }
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
        flow.error = nil
        do {
            let hint = Plan.meal(flow.slot).map { "This is my \($0.name.dropFirst(2))." }
            let a = try await scanner.analyze(text: text, hint: hint, context: context())
            flow.pending = ScanFlow.PendingMeal(image: nil, analysis: a, slot: flow.slot)
        } catch {
            flow.error = error.localizedDescription
        }
    }

    private func analyze(_ image: UIImage) async {
        flow.error = nil
        do {
            let hint = Plan.meal(flow.slot).map { "This is my \($0.name.dropFirst(2))." }
            let a = try await scanner.analyze(image, hint: hint, context: context())
            flow.pending = ScanFlow.PendingMeal(image: image, analysis: a, slot: flow.slot)
        } catch {
            flow.error = error.localizedDescription
        }
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
            if scanner.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.primary)
                    Text("Working out the nutrition…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 10)
            }
            if let error = flow.error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.top, 8)
            }
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
                        .disabled(scanner.isAnalyzing || !cloud.isSignedIn)
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
                            Text("Estimated from your description").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(alignment: .firstTextBaseline) {
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
                            if let g = FoodRating.grade(kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
                                                        fibre: m.fibre, sugar: m.sugar, sodium: m.sodium, satFat: m.satFat) {
                                FoodRatingBadge(grade: g).padding(.trailing, 4)
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
