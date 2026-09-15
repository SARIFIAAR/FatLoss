import SwiftUI
import PhotosUI

/// Adjust the max HR used for heart-rate zones (defaults to 220 − age).
struct MaxHRSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value: Int = 190

    var body: some View {
        NavigationStack {
            Form {
                Section("Maximum heart rate") {
                    Stepper("\(value) bpm", value: $value, in: 120...220)
                    Button("Reset to 220 − age (\(220 - (store.data.intake?.age ?? 30)))") {
                        store.setMaxHR(nil); dismiss()
                    }
                }
            }
            .navigationTitle("HR Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.setMaxHR(value); dismiss() } }
            }
            .onAppear { value = store.maxHR }
        }
    }
}

/// Body-composition tracker: trend graph of weight / fat mass / muscle mass over time, plus a
/// "+" to add a reading by photographing an InBody report (Claude vision) or entering it manually.
struct BodyCompTrackerCard: View {
    @Environment(Store.self) private var store
    @Environment(MealScanner.self) private var scanner
    @Environment(CloudSync.self) private var cloud

    @State private var showAdd = false
    @State private var showCamera = false
    @State private var showManual = false
    @State private var showAnalysis = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var draft: BodyCompEntry?
    @State private var error: String?
    @State private var metric: Metric = .fat

    enum Metric: String, CaseIterable { case weight = "Weight", fat = "Fat", muscle = "Muscle", pct = "Body Fat %" }

    private var entries: [BodyCompEntry] { store.bodyCompSorted }

    var body: some View {
        DarkCard {
            header
            if entries.isEmpty {
                emptyState
            } else {
                latestRow
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                TrendGraph(points: series, unit: unit, color: color)
                    .frame(height: 130)
                    .padding(.top, 10)
                Button { showAnalysis = true } label: {
                    HStack {
                        Text("Full body analysis").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(W.blue)
                    .padding(.top, 12)
                }
            }
        }
        .fullScreenCover(isPresented: $showAnalysis) { InBodyAnalysisView() }
        .onAppear { if UserDefaults.standard.bool(forKey: "openAnalysis") { showAnalysis = true } }
        .confirmationDialog("Add body composition", isPresented: $showAdd, titleVisibility: .visible) {
            Button("Scan InBody report") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            }
            Button("Choose from library") { /* PhotosPicker below opens via binding */ pickerTrigger = true }
            Button("Enter manually") { draft = BodyCompEntry(date: store.today, weightKg: store.currentWeight ?? 0); showManual = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in showCamera = false; if let img { Task { await scan(img) } } }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $pickerTrigger, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await scan(img)
                }
                pickerItem = nil
            }
        }
        .sheet(item: $draft) { d in
            BodyCompEntrySheet(entry: d, isFromPhoto: pendingImage != nil) { store.addBodyComp($0); pendingImage = nil }
        }
        .overlay {
            if scanner.isAnalyzing {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Reading your report…").font(.system(size: 13)).foregroundStyle(.white)
                    }
                }
            }
        }
        .alert("Couldn't read that", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @State private var pickerTrigger = false

    private func scan(_ image: UIImage) async {
        pendingImage = image
        do {
            let report = try await scanner.analyzeInBody(image)
            draft = report.entry(date: store.today)      // opens the sheet pre-filled for confirmation
        } catch {
            self.error = error.localizedDescription
            pendingImage = nil
        }
    }

    // MARK: Header / states

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BODY COMPOSITION TRACKER").font(W.label(12)).kerning(1.0).foregroundStyle(W.muted)
            Spacer()
            Button { showAdd = true } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(W.vibrant)
            }
        }
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track fat mass, muscle mass and body-fat % over time.")
                .font(.system(size: 13)).foregroundStyle(W.text)
            Text("Tap ＋ to photograph an InBody report — it's read automatically — or enter numbers by hand.")
                .font(.system(size: 11)).foregroundStyle(W.muted)
        }
        .padding(.vertical, 6)
    }

    private var latestRow: some View {
        let e = entries.last!
        return HStack(spacing: 0) {
            cell("Weight", String(format: "%.1f", e.weightKg), "kg")
            cell("Fat", e.fatKg.map { String(format: "%.1f", $0) } ?? "–", "kg")
            cell("Muscle", e.muscleKg.map { String(format: "%.1f", $0) } ?? "–", "kg")
            cell("Body fat", e.bodyFatPct.map { String(format: "%.1f", $0) } ?? "–", "%")
        }
    }

    private func cell(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(W.score(18)).foregroundStyle(W.text)
                Text(unit).font(.system(size: 10)).foregroundStyle(W.muted)
            }
            Text(label.uppercased()).font(W.label(9)).kerning(0.4).foregroundStyle(W.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Series

    private var series: [(date: Date, value: Double)] {
        entries.compactMap { e in
            let v: Double?
            switch metric {
            case .weight: v = e.weightKg
            case .fat: v = e.fatKg
            case .muscle: v = e.muscleKg
            case .pct: v = e.bodyFatPct
            }
            guard let v, let d = DateKey.date(e.date) else { return nil }
            return (d, v)
        }
    }
    private var unit: String { metric == .pct ? "%" : "kg" }
    private var color: Color {
        switch metric { case .weight: W.sleep; case .fat: W.yellow; case .muscle: W.vibrant; case .pct: W.blue }
    }
}

/// Minimal line graph with dots and first/last labels.
struct TrendGraph: View {
    let points: [(date: Date, value: Double)]
    let unit: String
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: pts[0])
                        for i in 1..<pts.count { p.addLine(to: pts[i]) }
                    }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                ForEach(pts.indices, id: \.self) { i in
                    Circle().fill(color).frame(width: 6, height: 6).position(pts[i])
                }
                if let first = points.first, let p0 = pts.first {
                    Text(String(format: "%.1f", first.value)).font(.system(size: 10)).foregroundStyle(W.muted)
                        .position(x: 18, y: max(10, p0.y - 12))
                }
                if points.count > 1, let last = points.last, let pl = pts.last {
                    Text(String(format: "%.1f %@", last.value, unit)).font(W.score(13)).foregroundStyle(color)
                        .position(x: geo.size.width - 24, y: max(10, pl.y - 12))
                }
                HStack {
                    Text(dateLabel(points.first?.date)).font(.system(size: 9)).foregroundStyle(W.muted)
                    Spacer()
                    Text(dateLabel(points.last?.date)).font(.system(size: 9)).foregroundStyle(W.muted)
                }
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height - 6)
            }
        }
    }

    private func layout(in size: CGSize) -> [CGPoint] {
        let vals = points.map(\.value)
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let span = max(hi - lo, 0.1)
        let w = size.width, h = size.height - 18
        return points.indices.map { i in
            let x = points.count <= 1 ? w / 2 : w * CGFloat(i) / CGFloat(points.count - 1)
            let y = h - CGFloat((points[i].value - lo) / span) * (h - 8) - 4
            return CGPoint(x: x, y: y)
        }
    }
    private func dateLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
    }
}

/// Confirm/edit a body-composition reading (pre-filled from a scanned report or blank for manual).
struct BodyCompEntrySheet: View {
    @State var entry: BodyCompEntry
    let isFromPhoto: Bool
    let onSave: (BodyCompEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                if isFromPhoto {
                    Section { Text("Read from your report — check the numbers and save.").font(.system(size: 13)) }
                }
                Section("Date") {
                    // Backfill historical InBody tests by setting the measurement date.
                    DatePicker("Measured on", selection: $day, in: ...Date(), displayedComponents: .date)
                }
                Section("Core") {
                    field("Weight (kg)", value: $entry.weightKg)
                    optField("Body fat (%)", value: $entry.bodyFatPct)
                    optField("Fat mass (kg)", value: $entry.fatMassKg)
                    optField("Skeletal muscle (kg)", value: $entry.muscleKg)
                    optField("BMR (kcal)", value: $entry.bmr)
                }
                Section("InBody detail (optional)") {
                    optField("Visceral fat level", value: $entry.visceralFat)
                    optField("Visceral fat area (cm²)", value: $entry.visceralFatArea)
                    optField("Total body water (L)", value: $entry.totalBodyWaterL)
                    optField("Protein (kg)", value: $entry.proteinKg)
                    optField("Mineral (kg)", value: $entry.mineralKg)
                    optField("InBody score", value: $entry.inbodyScore)
                }
            }
            .navigationTitle("Body Composition")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { day = DateKey.date(entry.date) ?? Date() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var e = entry; e.date = DateKey.key(day); onSave(e); dismiss()
                    }.disabled(entry.weightKg <= 0)
                }
            }
        }
    }

    private func field(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
    private func optField(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("—", value: value, format: .number).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}
