import SwiftUI
import PhotosUI

/// Shared photo → analysis → log flow, driven by the scan card and by each meal-plan row.
@Observable
final class ScanFlow {
    var slot: String?                      // meal key the photo belongs to (nil = other)
    var showCamera = false
    var showLibrary = false
    var pickerItem: PhotosPickerItem?
    var pending: PendingMeal?
    var error: String?
    var showTyped = false                  // FoodEntrySheet (database search / barcode / AI text)
    var typedStartsWithBarcode = false

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

    var body: some View {
        @Bindable var flow = flow
        let g = store.data.goals
        let ml = store.waterToday
        let pct = min(Double(ml) / Double(g.waterGoal), 1)
        Screen(subtitle: "Fuel your fat loss", title: "Nutrition 🥗") {
            MealScanCard(flow: flow)
            MealPlanCard(flow: flow)
            TodayMealsCard()
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                if Calendar.current.component(.hour, from: ctx.date) >= Plan.kitchenClosesHour {
                    HStack(spacing: 10) {
                        Text("🌙")
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
                SectionTitle("💧 Water Tracker")
                VStack(spacing: 2) {
                    Text("\(ml)").font(.system(size: 52, weight: .black)).foregroundStyle(Theme.primary)
                    Text("ml out of \(g.waterGoal.formatted())").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                WaveView(fraction: pct).padding(.vertical, 10)
                HStack(spacing: 10) {
                    Button("+ 250 ml") { store.addWater(250) }.buttonStyle(PrimaryButtonStyle())
                    Button("+ 500 ml") { store.addWater(500) }.buttonStyle(PrimaryButtonStyle())
                    Button("Reset") { store.resetWater() }.buttonStyle(SecondaryButtonStyle())
                }
            }

            Card {
                let t = store.totals()
                SectionTitle("Today vs Targets")
                VStack(spacing: 10) {
                    MacroBar(name: "🔥 Calories", value: "\(Int(t.kcal.rounded())) / \(g.kcal) kcal",
                             fraction: t.kcal / Double(g.kcal), color: t.kcal > Double(g.kcal) ? Theme.red : Theme.primaryLight)
                    MacroBar(name: "🥩 Protein", value: "\(Int(t.protein.rounded())) / \(g.protein) g",
                             fraction: t.protein / Double(g.protein), color: Theme.primary)
                    MacroBar(name: "🍚 Carbs", value: "\(Int(t.carbs.rounded())) / \(g.carbs) g",
                             fraction: t.carbs / Double(g.carbs), color: Theme.orange)
                    MacroBar(name: "🥑 Fat", value: "\(Int(t.fat.rounded())) / \(g.fat) g",
                             fraction: t.fat / Double(g.fat), color: Theme.blue)
                }
                Text("\(max(0, g.kcal - Int(t.kcal.rounded()))) kcal left today · target \(g.kcal.formatted()) kcal (−\(g.deficit) deficit)")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .padding(.top, 10)
                let e = store.energy()
                if let burned = e.burned {
                    let net = burned - t.kcal
                    HStack(spacing: 6) {
                        Text("⌚ Burned \(Int(burned)) kcal").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                        Text("·").foregroundStyle(Theme.muted)
                        Text(t.kcal > 0 ? "\(net >= 0 ? "Deficit" : "Surplus") \(Int(abs(net))) kcal so far" : "log meals to see the deficit")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(t.kcal == 0 ? Theme.muted : net >= Double(g.deficit) ? Theme.primary : net >= 0 ? Theme.blue : Theme.red)
                    }
                    .padding(.top, 4)
                    if let avg = store.averageDeficit(days: 7) {
                        Text("7-day average \(avg >= 0 ? "deficit" : "surplus") \(Int(abs(avg))) kcal/day · goal \(g.deficit)")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
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
            MealResultSheet(image: p.image, analysis: p.analysis, slot: p.slot) { entry in
                store.addMeal(entry)
                flow.pending = nil
            }
        }
        .sheet(isPresented: $flow.showTyped) {
            FoodEntrySheet(slot: flow.slot, startWithBarcode: flow.typedStartsWithBarcode) { entry in
                store.addMeal(entry)
                flow.showTyped = false
            } onAIEstimate: { text in
                flow.showTyped = false
                Task { await analyze(text: text) }
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

struct MealScanCard: View {
    @Bindable var flow: ScanFlow
    @Environment(MealScanner.self) private var scanner
    @Environment(CloudSync.self) private var cloud

    var body: some View {
        Card {
            SectionTitle("🍽️ Log a meal")
            Text("Photo, typed search or barcode — each meal below has all three. Photos and descriptions are estimated by the dietitian model; typed foods and barcodes use the USDA / Open Food Facts nutrition databases.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                .padding(.bottom, 10)
            if !cloud.isSignedIn {
                Text("Sign in with Apple in the Profile tab to enable meal logging.")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 10) {
                Button {
                    flow.camera(slot: nil)
                } label: {
                    Label(scanner.isAnalyzing ? "Analyzing…" : "Camera", systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(scanner.isAnalyzing || !cloud.isSignedIn || !UIImagePickerController.isSourceTypeAvailable(.camera))

                PhotosPicker(selection: $flow.pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent, lineWidth: 2))
                }
                .simultaneousGesture(TapGesture().onEnded { flow.slot = nil; flow.error = nil })
                .disabled(scanner.isAnalyzing || !cloud.isSignedIn)
            }
            HStack(spacing: 10) {
                Button { flow.typed(slot: nil) } label: { Label("Type it in", systemImage: "keyboard") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { flow.typed(slot: nil, barcode: true) } label: { Label("Barcode", systemImage: "barcode.viewfinder") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 10)
            .disabled(scanner.isAnalyzing || !cloud.isSignedIn)
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
    @Environment(Store.self) private var store
    @Environment(MealScanner.self) private var scanner
    @Environment(CloudSync.self) private var cloud

    var body: some View {
        Card {
            SectionTitle("Meal Plan")
            VStack(spacing: 0) {
                ForEach(Array(Plan.meals.enumerated()), id: \.element.id) { i, m in
                    let eaten = store.kcal(slot: m.key)
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
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(eaten > Double(m.targetKcal) * 1.25 ? Theme.red : Theme.primary)
                                Text("plan \(m.kcal)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                            } else {
                                Text(m.kcal).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                        }
                        Menu {
                            Button { flow.camera(slot: m.key) } label: { Label("Take photo", systemImage: "camera.fill") }
                            Button { flow.slot = m.key; flow.error = nil; flow.showLibrary = true } label: { Label("Choose from library", systemImage: "photo.on.rectangle") }
                            Divider()
                            Button { flow.typed(slot: m.key) } label: { Label("Type it in", systemImage: "keyboard") }
                            Button { flow.typed(slot: m.key, barcode: true) } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
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
            Text("⏰ Kitchen closes at 9:00 PM — no food after this")
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0x8B5E3C))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(hex: 0xFFF8F0))
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
    var slot: String? = nil
    let onAdd: (MealEntry) -> Void
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

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
                            Text("✨")
                            Text("Estimated from your description").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let m = Plan.meal(slot) {
                        Text("Logging as \(m.name) · plan \(m.kcal)")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(analysis.meal_name).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(analysis.confidence.capitalized) confidence")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(analysis.confidence == "high" ? Theme.primary : Theme.orange)
                            .padding(.vertical, 3).padding(.horizontal, 8)
                            .background((analysis.confidence == "high" ? Theme.primary : Theme.orange).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        MacroStat(value: "\(Int(analysis.total_kcal.rounded()))", label: "kcal", color: Theme.primary)
                        MacroStat(value: "\(Int(analysis.total_protein_g.rounded()))g", label: "protein", color: Theme.primary)
                        MacroStat(value: "\(Int(analysis.total_carbs_g.rounded()))g", label: "carbs", color: Theme.orange)
                        MacroStat(value: "\(Int(analysis.total_fat_g.rounded()))g", label: "fat", color: Theme.blue)
                    }
                    .padding(.vertical, 12)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 0) {
                        ForEach(Array(analysis.items.enumerated()), id: \.offset) { i, it in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                    Text("\(it.portion) · P \(Int(it.protein_g.rounded())) · C \(Int(it.carbs_g.rounded())) · F \(Int(it.fat_g.rounded()))")
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("\(Int(it.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                            }
                            .padding(.vertical, 9)
                            if i < analysis.items.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }

                    if !analysis.notes.isEmpty {
                        Text("ℹ️ \(analysis.notes)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                    }

                    Button(Plan.meal(slot).map { "Log as \($0.name)" } ?? "Add to today's log") {
                        var e = analysis.mealEntry(date: store.today)
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
    @Environment(Store.self) private var store

    var body: some View {
        let meals = store.mealsToday
        if !meals.isEmpty {
            Card {
                SectionTitle("🍽️ Eaten today")
                VStack(spacing: 0) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { i, m in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                Text("\(Plan.meal(m.slot).map { $0.name + " · " } ?? "")\(m.time.formatted(date: .omitted, time: .shortened)) · P \(Int(m.protein.rounded())) · C \(Int(m.carbs.rounded())) · F \(Int(m.fat.rounded()))")
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(Int(m.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                            Button(role: .destructive) { store.deleteMeal(m) } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 6)
                        }
                        .padding(.vertical, 9)
                        if i < meals.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
            }
        }
    }
}
