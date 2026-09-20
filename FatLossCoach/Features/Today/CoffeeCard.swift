import SwiftUI

/// Today's coffee tracker — shows the day's espresso-shot count as cup icons, total caffeine,
/// and a quick logger (Starbucks-style sizes → shots). Feeds the caffeine recovery/stress signal.
struct CoffeeCard: View {
    @Environment(Store.self) private var store
    @State private var showLog = false

    var body: some View {
        let t = store.caffeineToday()
        let shots = t.shots
        Card(accent: shots >= 4 ? Theme.orange : nil) {
            HStack {
                Text("COFFEE").font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                Spacer()
                if t.mg > 0 {
                    Text("\(Int(t.mg.rounded())) mg caffeine")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.mg >= 400 ? Theme.red : Theme.muted)
                }
            }
            .padding(.bottom, 8)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(shotsLabel(shots)).font(Theme.score(34)).foregroundStyle(shots > 0 ? Theme.text : Theme.muted)
                        Text(shots == 1 ? "shot" : "shots").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Text(t.count == 0 ? "No coffee yet" : "\(t.count) drink\(t.count == 1 ? "" : "s") today")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                cups(shots)
            }

            if store.lateCaffeineToday() {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundStyle(Theme.orange)
                    Text("Caffeine after 2 pm can dent tonight's sleep & recovery.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                Button { showLog = true } label: {
                    Label("Log coffee", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle(compact: true))
                if t.count > 0 {
                    Button { store.removeLastCoffee() } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 44)
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.top, 12)
        }
        .sheet(isPresented: $showLog) { CoffeeLogSheet() }
    }

    private func shotsLabel(_ s: Double) -> String {
        s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)
    }

    /// Up to ~8 filled cup glyphs representing shots (rounded), then "+N".
    private func cups(_ shots: Double) -> some View {
        let full = min(8, Int(shots.rounded()))
        let extra = max(0, Int(shots.rounded()) - 8)
        return HStack(spacing: 3) {
            ForEach(0..<max(full, 0), id: \.self) { _ in
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 15)).foregroundStyle(Theme.primary)
            }
            if full == 0 {
                Image(systemName: "cup.and.saucer").font(.system(size: 15)).foregroundStyle(Theme.muted.opacity(0.5))
            }
            if extra > 0 { Text("+\(extra)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary) }
        }
    }
}

/// Quick logger — tap a size/drink to log its shots + caffeine (and calories for milk drinks).
struct CoffeeLogSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var showSearch = false
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tap a drink to log it. Milk & syrup drinks add their calories to Nutrition automatically; black coffee is caffeine only.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)

                    // Add your own / search the database
                    HStack(spacing: 10) {
                        actionTile(icon: "plus", title: "Add custom") { showCustom = true }
                        actionTile(icon: "magnifyingglass", title: "Search database") { showSearch = true }
                    }

                    ForEach(CoffeeCatalog.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title.uppercased()).font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(section.items) { p in tile(p) }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Log coffee").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showCustom) { CustomCoffeeSheet { store.logCoffee($0); dismiss() } }
            .sheet(isPresented: $showSearch) {
                FoodEntrySheet(slot: "snack", initialQuery: "coffee",
                               onLog: { store.addMeal($0); showSearch = false; dismiss() },
                               onAIEstimate: { _ in showSearch = false })
            }
        }
    }

    private func actionTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func tile(_ p: CoffeePreset) -> some View {
        Button { store.logCoffee(p); dismiss() } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon).font(.system(size: 16)).foregroundStyle(Theme.primary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(subtitle(p)).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func subtitle(_ p: CoffeePreset) -> String {
        let s = p.shots == p.shots.rounded() ? String(Int(p.shots)) : String(format: "%.1f", p.shots)
        var parts = ["\(s) shot\(p.shots == 1 ? "" : "s")", "\(Int(p.mg)) mg"]
        if p.kcal > 0 { parts.append("\(Int(p.kcal)) kcal") }
        return parts.joined(separator: " · ")
    }
}

/// Add-your-own drink — name, shots, caffeine, and (optional) calories that flow to Nutrition.
struct CustomCoffeeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CoffeePreset) -> Void

    @State private var name = ""
    @State private var shots = 1.0
    @State private var mg = 120.0
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    TextField("Name (e.g. Cortado, Chai Latte)", text: $name)
                }
                Section("Caffeine") {
                    stepperRow("Espresso shots", value: $shots, step: 0.5, range: 0...8, fmt: shotsFmt)
                    stepperRow("Caffeine", value: $mg, step: 10, range: 0...600, suffix: "mg")
                }
                Section {
                    stepperRow("Calories", value: $kcal, step: 10, range: 0...900, suffix: "kcal")
                    if kcal > 0 {
                        stepperRow("Protein", value: $protein, step: 1, range: 0...80, suffix: "g")
                        stepperRow("Carbs", value: $carbs, step: 1, range: 0...120, suffix: "g")
                        stepperRow("Fat", value: $fat, step: 1, range: 0...80, suffix: "g")
                    }
                } header: { Text("Nutrition") } footer: {
                    Text(kcal > 0 ? "This drink will also be added to today's Nutrition." : "Leave calories at 0 for black coffee — it stays caffeine-only.")
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Custom drink").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let icon = kcal > 0 ? "cup.and.saucer.fill" : "cup.and.saucer"
                        onSave(CoffeePreset(id: "custom", name: n.isEmpty ? "Coffee" : n, icon: icon,
                                            shots: shots, mg: mg, kcal: kcal, protein: protein, carbs: carbs, fat: fat))
                    }.fontWeight(.bold)
                }
            }
        }
    }

    private func shotsFmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private func stepperRow(_ label: String, value: Binding<Double>, step: Double, range: ClosedRange<Double>,
                            suffix: String = "", fmt: ((Double) -> String)? = nil) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label).foregroundStyle(Theme.text)
                Spacer()
                Text("\(fmt?(value.wrappedValue) ?? String(Int(value.wrappedValue)))\(suffix.isEmpty ? "" : " \(suffix)")")
                    .foregroundStyle(Theme.muted).font(.system(size: 14, weight: .semibold))
            }
        }
    }
}
