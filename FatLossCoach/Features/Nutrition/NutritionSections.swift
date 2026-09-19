import SwiftUI

/// The three Lifesum-style sections of the Nutrition tab, in the HUMANS design language.
enum NutritionSection: String, CaseIterable, Identifiable {
    case diary = "Diary", program = "Program", recipes = "Recipes"
    var id: String { rawValue }
}

/// Reusable pill segmented control (our theme).
struct SegmentedTabs<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value.id) { opt in
                let sel = selection == opt.value
                Button { withAnimation(.easeInOut(duration: 0.15)) { selection = opt.value } } label: {
                    Text(opt.label).font(.system(size: 14, weight: .bold))
                        .foregroundStyle(sel ? Color(hex: 0x101518) : Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(sel ? Theme.primary : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

/// Diary top summary — Lifesum-style calorie ring ("calories left") + eaten/burned + macro bars.
struct DiarySummaryCard: View {
    @Environment(Store.self) private var store
    let day: String

    var body: some View {
        let g = store.data.goals
        let t = store.totals(on: day)
        let eaten = Int(t.kcal.rounded())
        let over = eaten > g.kcal
        let left = abs(g.kcal - eaten)
        let frac = g.kcal > 0 ? min(1, t.kcal / Double(g.kcal)) : 0
        let isToday = day == store.today
        let e = store.energy()
        let burned = isToday ? e.burned : nil

        Card(accent: over ? Theme.red : Theme.primary) {
            HStack(alignment: .center) {
                sideStat("EATEN", "\(eaten)", Theme.text)
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 10)
                    Circle().trim(from: 0, to: max(0.001, frac))
                        .stroke(over ? Theme.red : Theme.primary,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: (over ? Theme.red : Theme.primary).opacity(0.5), radius: 6)
                    VStack(spacing: 0) {
                        Text("\(left)").font(W.score(30)).foregroundStyle(Theme.text)
                        Text(over ? "kcal over" : "kcal left").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 116, height: 116)
                Spacer()
                sideStat("BURNED", burned.map { "\(Int($0))" } ?? "–", Theme.orange)
            }

            HStack(spacing: 10) {
                macroMini("Protein", t.protein, g.protein, Theme.primary)
                macroMini("Carbs", t.carbs, g.carbs, Theme.orange)
                macroMini("Fat", t.fat, g.fat, Theme.blue)
            }
            .padding(.top, 14)

            if let burned, isToday {
                let net = burned - t.kcal
                Text(t.kcal > 0
                     ? "\(net >= 0 ? "Deficit" : "Surplus") \(Int(abs(net))) kcal so far · goal −\(g.deficit)"
                     : "Log meals to see today's deficit")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 10)
            }
        }
    }

    private func sideStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(W.score(20)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .bold)).kerning(0.5).foregroundStyle(Theme.muted)
        }
        .frame(width: 64)
    }

    private func macroMini(_ name: String, _ value: Double, _ goal: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(name.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(value.rounded()))/\(goal)g").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card2)
                    Capsule().fill(color).frame(width: max(3, geo.size.width * min(1, goal > 0 ? value / Double(goal) : 0)))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Program section (diet plans)

struct ProgramSection: View {
    @Environment(Store.self) private var store
    @State private var selected: DietProgram?

    var body: some View {
        VStack(spacing: 12) {
            Text("Pick a plan — it sets your macro targets and filters recipes.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(ProgramCatalog.all) { p in
                Button { selected = p } label: { card(p) }.buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { ProgramDetailView(program: $0) }
    }

    private func card(_ p: DietProgram) -> some View {
        let active = p.id == store.data.nutritionPlanId
        return Card(accent: active ? p.color : nil) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(p.color.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: p.icon).font(.system(size: 18)).foregroundStyle(p.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                        if active {
                            Text("ACTIVE").font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color(hex: 0x101518))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(p.color, in: Capsule())
                        }
                    }
                    Text(p.tagline).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("C \(p.carbPct)% · P \(p.proteinPct)% · F \(p.fatPct)%")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct ProgramDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(program.color.opacity(0.18)).frame(width: 56, height: 56)
                            Image(systemName: program.icon).font(.system(size: 24)).foregroundStyle(program.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name).font(Theme.titleL).foregroundStyle(Theme.text)
                            Text(program.tagline).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }
                    Text(program.about).font(.system(size: 14)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Card {
                        Text("MACRO SPLIT").font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                        let m = program.macros(forKcal: store.data.goals.kcal)
                        HStack(spacing: 10) {
                            split("Carbs", program.carbPct, "\(m.carbs)g", Theme.orange)
                            split("Protein", program.proteinPct, "\(m.protein)g", Theme.primary)
                            split("Fat", program.fatPct, "\(m.fat)g", Theme.blue)
                        }.padding(.top, 8)
                        Text("Based on your \(store.data.goals.kcal) kcal target.")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 8)
                    }

                    listCard("EAT", program.eat, "checkmark", Theme.primary)
                    listCard("LIMIT", program.avoid, "xmark", Theme.red)

                    Card {
                        Text("SAMPLE DAY").font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                        ForEach(Array(program.sampleDay.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 10) {
                                Text(["Breakfast", "Lunch", "Dinner"][min(i, 2)])
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(program.color).frame(width: 74, alignment: .leading)
                                Text(s).font(.system(size: 13)).foregroundStyle(Theme.text)
                                Spacer()
                            }.padding(.vertical, 6)
                            if i < program.sampleDay.count - 1 { Divider().overlay(Theme.border) }
                        }.padding(.top, 6)
                    }

                    Button {
                        store.chooseProgram(program); dismiss()
                    } label: {
                        Text(program.id == store.data.nutritionPlanId ? "Restart this plan" : "Start this plan")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Plan").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func split(_ name: String, _ pct: Int, _ grams: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(pct)%").font(W.score(22)).foregroundStyle(color)
            Text(grams).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            Text(name.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity)
    }

    private func listCard(_ title: String, _ items: [String], _ icon: String, _ color: Color) -> some View {
        Card {
            Text(title).font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color).frame(width: 16)
                    Text(item).font(.system(size: 13)).foregroundStyle(Theme.text)
                    Spacer()
                }.padding(.vertical, 5)
            }.padding(.top, 6)
        }
    }
}

// MARK: - Recipes section

struct RecipesSection: View {
    @Environment(Store.self) private var store
    @State private var category = "All"
    @State private var selected: Recipe?

    private var filtered: [Recipe] {
        var list = RecipeCatalog.all
        if category != "All" { list = list.filter { $0.category == category } }
        if let plan = store.data.nutritionPlanId {   // active plan floats matching recipes up
            list.sort { ($0.tags.contains(plan) ? 0 : 1) < ($1.tags.contains(plan) ? 0 : 1) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All")
                    ForEach(RecipeCatalog.categories, id: \.self) { chip($0) }
                }
            }
            ForEach(filtered) { r in
                Button { selected = r } label: { card(r) }.buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { RecipeDetailView(recipe: $0) }
    }

    private func chip(_ c: String) -> some View {
        let sel = category == c
        return Button { category = c } label: {
            Text(c).font(.system(size: 13, weight: .bold))
                .foregroundStyle(sel ? Color(hex: 0x101518) : Theme.muted)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(sel ? Theme.primary : Theme.card, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func card(_ r: Recipe) -> some View {
        let matches = store.data.nutritionPlanId.map { r.tags.contains($0) } ?? false
        return Card(accent: matches ? r.color : nil) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(r.color.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: r.icon).font(.system(size: 18)).foregroundStyle(r.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("\(r.category) · \(r.minutes) min").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("\(r.kcal) kcal · P \(r.protein) · C \(r.carbs) · F \(r.fat)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct RecipeDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(recipe.color.opacity(0.18)).frame(width: 56, height: 56)
                            Image(systemName: recipe.icon).font(.system(size: 24)).foregroundStyle(recipe.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name).font(Theme.titleL).foregroundStyle(Theme.text)
                            Text("\(recipe.category) · \(recipe.minutes) min").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                    }
                    Card {
                        HStack {
                            macro("\(recipe.kcal)", "KCAL", Theme.primary)
                            macro("\(recipe.protein)g", "PROTEIN", Theme.primary)
                            macro("\(recipe.carbs)g", "CARBS", Theme.orange)
                            macro("\(recipe.fat)g", "FAT", Theme.blue)
                        }
                    }
                    listCard("INGREDIENTS", recipe.ingredients, numbered: false)
                    listCard("METHOD", recipe.steps, numbered: true)

                    Button { store.logRecipe(recipe); dismiss() } label: {
                        Text("Log to diary").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func macro(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(W.score(18)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity)
    }

    private func listCard(_ title: String, _ items: [String], numbered: Bool) -> some View {
        Card {
            Text(title).font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 10) {
                    if numbered {
                        Text("\(i + 1)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.primary).frame(width: 16, alignment: .leading)
                    } else {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.muted).frame(width: 16).padding(.top, 6)
                    }
                    Text(item).font(.system(size: 13)).foregroundStyle(Theme.text)
                    Spacer()
                }.padding(.vertical, 5)
            }.padding(.top, 6)
        }
    }
}
