import SwiftUI

/// Type-it-in meal logging: search the nutrition database (or scan a barcode), pick portions,
/// build the meal from one or more foods, and log it against a meal slot.
struct FoodEntrySheet: View {
    let onLog: (MealEntry) -> Void
    let onAIEstimate: (String) -> Void
    private let startWithBarcode: Bool
    @State private var slot: String?

    init(slot: String?, startWithBarcode: Bool = false, onLog: @escaping (MealEntry) -> Void, onAIEstimate: @escaping (String) -> Void) {
        self.onLog = onLog
        self.onAIEstimate = onAIEstimate
        self.startWithBarcode = startWithBarcode
        _slot = State(initialValue: slot)
    }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var db = FoodSearch()
    @State private var query = ""
    @State private var results: [FoodSearch.Food] = []
    @State private var error: String?
    @State private var basket: [BasketItem] = []
    @State private var picking: FoodSearch.Food?
    @State private var showBarcode = false
    @State private var lookingUpBarcode = false
    @FocusState private var searchFocused: Bool

    struct BasketItem: Identifiable {
        let id = UUID()
        var food: FoodSearch.Food
        var portionLabel: String
        var grams: Double
        var macros: FoodSearch.Macros { food.per100.scaled(grams / 100) }
    }

    private var total: FoodSearch.Macros { basket.map(\.macros).reduce(FoodSearch.Macros(), +) }
    private var mealName: String {
        let names = basket.map { item -> String in
            if let b = item.food.brand, !b.isEmpty { return "\(b) \(item.food.name)" }
            return item.food.name.components(separatedBy: ",").first ?? item.food.name
        }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? shown + " +\(names.count - 3)" : shown
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("e.g. grilled chicken breast, oats, labneh", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                        if !query.isEmpty {
                            Button { query = ""; results = [] } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showBarcode = true } label: {
                            Image(systemName: "barcode.viewfinder").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    if db.isSearching || lookingUpBarcode {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.primary)
                            Text(lookingUpBarcode ? "Looking up product…" : "Searching USDA database…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.red)
                    }
                } header: {
                    Text("Search a food or scan its barcode")
                }

                if !results.isEmpty {
                    Section("Results · per 100 g") {
                        ForEach(results) { food in
                            Button { picking = food } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                                        Text("\(food.subtitle) · P \(Int(food.per100.protein.rounded())) · C \(Int(food.per100.carbs.rounded())) · F \(Int(food.per100.fat.rounded()))")
                                            .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(Int(food.per100.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                if query.trimmingCharacters(in: .whitespaces).count >= 3 && !db.isSearching {
                    Section {
                        Button {
                            onAIEstimate(query)
                        } label: {
                            HStack(spacing: 10) {
                                Text("✨")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ask AI to estimate “\(query.trimmingCharacters(in: .whitespaces))”")
                                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                    Text(results.isEmpty ? "Nothing matched — describe the whole meal and the dietitian model estimates it."
                                                         : "Or describe the whole meal in one line (“2 eggs, toast, black coffee”).")
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }

                if !basket.isEmpty {
                    Section {
                        ForEach(basket) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.food.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(item.portionLabel) · P \(Int(item.macros.protein.rounded())) · C \(Int(item.macros.carbs.rounded())) · F \(Int(item.macros.fat.rounded()))")
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("\(Int(item.macros.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                            }
                        }
                        .onDelete { basket.remove(atOffsets: $0) }
                        HStack(spacing: 8) {
                            MacroStat(value: "\(Int(total.kcal.rounded()))", label: "kcal", color: Theme.primary)
                            MacroStat(value: "\(Int(total.protein.rounded()))g", label: "protein", color: Theme.primary)
                            MacroStat(value: "\(Int(total.carbs.rounded()))g", label: "carbs", color: Theme.orange)
                            MacroStat(value: "\(Int(total.fat.rounded()))g", label: "fat", color: Theme.blue)
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text(Plan.meal(slot).map { "Your \($0.name.dropFirst(2))" } ?? "Your meal")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if !basket.isEmpty {
                    VStack(spacing: 10) {
                    SlotPicker(slot: $slot)
                    Button(Plan.logLabel(slot)) {
                        var e = MealEntry(date: store.today, name: mealName, kcal: total.kcal, protein: total.protein,
                                          carbs: total.carbs, fat: total.fat,
                                          items: basket.map { FoodItem(name: $0.food.name, portion: $0.portionLabel, grams: $0.grams,
                                                                       kcal: $0.macros.kcal, protein: $0.macros.protein,
                                                                       carbs: $0.macros.carbs, fat: $0.macros.fat) },
                                          confidence: "high", notes: "Nutrition database values (USDA / Open Food Facts).")
                        e.slot = slot
                        onLog(e)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.bg)
                }
            }
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else { results = []; return }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                error = nil
                do { results = try await db.search(q) }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onAppear {
                if startWithBarcode { showBarcode = true } else { searchFocused = true }
            }
            .sheet(item: $picking) { food in
                PortionSheet(food: food) { label, grams in
                    basket.append(BasketItem(food: food, portionLabel: label, grams: grams))
                    picking = nil
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showBarcode) {
                BarcodeScannerView { code in Task { await lookup(code) } }
            }
        }
    }

    private func lookup(_ code: String) async {
        lookingUpBarcode = true
        error = nil
        defer { lookingUpBarcode = false }
        do { picking = try await db.barcode(code) }
        catch { self.error = error.localizedDescription }
    }
}

/// Choose the portion for one food: a household measure or grams, times a quantity.
struct PortionSheet: View {
    let food: FoodSearch.Food
    let onAdd: (String, Double) -> Void

    @State private var choice: String
    @State private var customGrams = "100"
    @State private var quantity = 1.0
    private static let custom = "__grams__"

    init(food: FoodSearch.Food, onAdd: @escaping (String, Double) -> Void) {
        self.food = food
        self.onAdd = onAdd
        _choice = State(initialValue: food.servings.first?.label ?? Self.custom)
    }

    private var gramsEach: Double {
        if choice == Self.custom { return max(0, Fmt.parse(customGrams) ?? 0) }
        return food.servings.first { $0.label == choice }?.grams ?? 0
    }
    private var grams: Double { gramsEach * quantity }
    private var macros: FoodSearch.Macros { food.per100.scaled(grams / 100) }
    private var label: String {
        let q = Fmt.num(quantity)
        if choice == Self.custom { return "\(Int(grams.rounded())) g" }
        let base = choice.replacingOccurrences(of: #" \(\d+ g\)$"#, with: "", options: .regularExpression)
        return quantity == 1 ? "\(base) (\(Int(grams.rounded())) g)" : "\(q) × \(base) (\(Int(grams.rounded())) g)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(food.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("\(food.subtitle) · \(Int(food.per100.kcal.rounded())) kcal per 100 g")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Section("Portion") {
                    Picker("Measure", selection: $choice) {
                        ForEach(food.servings) { s in Text(s.label).tag(s.label) }
                        Text("Grams").tag(Self.custom)
                    }
                    .pickerStyle(.menu)
                    if choice == Self.custom {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("100", text: $customGrams).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                            Text("g").foregroundStyle(Theme.muted)
                        }
                    }
                    Stepper(value: $quantity, in: 0.25...20, step: 0.25) {
                        HStack { Text("Quantity"); Spacer(); Text("× \(Fmt.num(quantity))").foregroundStyle(Theme.muted) }
                    }
                }
                Section {
                    HStack(spacing: 8) {
                        MacroStat(value: "\(Int(macros.kcal.rounded()))", label: "kcal", color: Theme.primary)
                        MacroStat(value: "\(Int(macros.protein.rounded()))g", label: "protein", color: Theme.primary)
                        MacroStat(value: "\(Int(macros.carbs.rounded()))g", label: "carbs", color: Theme.orange)
                        MacroStat(value: "\(Int(macros.fat.rounded()))g", label: "fat", color: Theme.blue)
                    }
                    Button("Add \(label)") { onAdd(label, grams) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(grams <= 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
