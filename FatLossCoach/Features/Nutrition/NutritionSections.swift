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

/// One-time nudge to adopt "Log with AI" as the fast default (dismissible).
struct AINudgeBanner: View {
    @Environment(Store.self) private var store
    let onTap: () -> Void
    @AppStorage("aiNudgeDismissed") private var dismissed = false

    var body: some View {
        // Show until the user dismisses it or has clearly adopted AI (3+ AI logs).
        if !dismissed && store.aiLogCount < 3 {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.primary.opacity(0.18)).frame(width: 34, height: 34)
                        Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(Theme.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Log faster with AI").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.text)
                        Text("Snap a photo or just say what you ate — one tap.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).padding(6)
                    }.buttonStyle(.plain)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.primary.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Fasting window card — shown in the Diary when a fasting plan (16:8) is active.
struct FastingCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        if let p = store.nutritionPlan, let f = p.fasting {
            Card(accent: p.color) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(p.color.opacity(0.18)).frame(width: 40, height: 40)
                        Image(systemName: "clock.fill").font(.system(size: 17)).foregroundStyle(p.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(f.label) fasting").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                        Text(f.blurb).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                if f.eatingWindowHours > 0 {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        let hour = Calendar.current.component(.hour, from: ctx.date)
                        let start = 12, end = start + f.eatingWindowHours     // default noon → window
                        let eating = hour >= start && hour < end
                        HStack(spacing: 6) {
                            Circle().fill(eating ? p.color : Theme.muted).frame(width: 8, height: 8)
                            Text(eating ? "Eating window open · closes \(end):00" : (hour < start ? "Fasting · window opens \(start):00" : "Fasting until tomorrow \(start):00"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(eating ? Theme.text : Theme.muted)
                            Spacer()
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }
}

/// Slim banner shown in the Diary when a diet program is active.
struct ActivePlanBanner: View {
    @Environment(Store.self) private var store
    var body: some View {
        if let p = store.nutritionPlan {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(p.color.opacity(0.2)).frame(width: 30, height: 30)
                    Image(systemName: p.icon).font(.system(size: 13)).foregroundStyle(p.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(p.name) plan").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("C \(p.carbPct)% · P \(p.proteinPct)% · F \(p.fatPct)%")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(hex: 0x101518))
                    .padding(.horizontal, 7).padding(.vertical, 3).background(p.color, in: Capsule())
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.color.opacity(0.4), lineWidth: 1))
        }
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
        let isToday = day == store.today
        let e = store.energy()
        let burned = isToday ? e.burned : nil
        // Net mode (Lifesum default): the day's allowance grows by what the Watch says you burned.
        // Gross mode: the allowance is just the target; burn is shown but not added.
        let net = g.countBurnedCalories
        let budget = net ? g.kcal + Int((burned ?? 0).rounded()) : g.kcal
        let over = eaten > budget
        let left = abs(budget - eaten)
        let frac = budget > 0 ? min(1, t.kcal / Double(budget)) : 0

        let planId = store.data.nutritionPlanId
        let meals = store.meals(on: day)
        let lifeScore = LifeScore.score(meals: meals, goals: g, planId: planId)
        let dayRating = FoodRating.rateDay(meals: meals, planId: planId)
        Card(accent: over ? Theme.red : Theme.primary) {
            if let ls = lifeScore {
                HStack(spacing: 8) {
                    // Day-level plan-aware grade sits beside the Life Score number — same calculation,
                    // two faces (the badge explains WHY; the number is the diary headline).
                    if let dr = dayRating {
                        RatingBadgeButton(rating: dr, size: 22, title: "Day rating")
                    }
                    Text("LIFE SCORE").font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                    Text("\(ls)").font(.system(size: 13, weight: .heavy)).foregroundStyle(LifeScore.color(ls))
                    Text(LifeScore.label(ls)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.card2)
                            Capsule().fill(LifeScore.color(ls)).frame(width: max(4, geo.size.width * Double(ls) / 100))
                        }
                    }.frame(width: 70, height: 5)
                }
                .padding(.bottom, 10)
            }
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
                let bal = burned - t.kcal
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.kcal > 0
                         ? "\(bal >= 0 ? "Deficit" : "Surplus") \(Int(abs(bal))) kcal so far · goal −\(g.deficit)"
                         : "Log meals to see today's deficit")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text(net
                         ? "Net calories: your \(g.kcal) target grows by the \(Int(burned)) kcal you burned."
                         : "Gross calories: allowance is your \(g.kcal) target; burn is shown, not added.")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted).opacity(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
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
    @State private var recipe: Recipe?
    @State private var swapping: SlotID?     // slot being swapped

    struct SlotID: Identifiable { let id: String }

    var body: some View {
        VStack(spacing: 12) {
            if store.nutritionPlan != nil { planCard }
            Text("Pick a plan — it sets your macro targets and filters recipes.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(ProgramCatalog.all) { p in
                Button { selected = p } label: { card(p) }.buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { ProgramDetailView(program: $0) }
        .sheet(item: $recipe) { RecipeDetailView(recipe: $0) }
        .sheet(item: $swapping) { RecipeSwapSheet(slot: $0.id) }
    }

    private var planCard: some View {
        let plan = store.nutritionPlan
        let slots = Store.planSlots
        let picked = slots.compactMap { store.plannedRecipe($0) }
        let total = picked.reduce(0) { $0 + $1.kcal }
        return Card(accent: plan?.color) {
            HStack {
                Text("MY MEAL PLAN").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                Spacer()
                if store.hasPlan { Text("\(total) kcal").font(.system(size: 12, weight: .heavy)).foregroundStyle(plan?.color ?? Theme.primary) }
            }
            .padding(.bottom, 8)
            if !store.hasPlan {
                Text("Build a day of meals from your plan — swap any meal, then log with one tap.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.bottom, 10)
                Button { store.generatePlan() } label: {
                    Label("Generate my day", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                        if let r = store.plannedRecipe(slot) {
                            HStack(spacing: 10) {
                                Text(slot.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 62, alignment: .leading)
                                Button { recipe = r } label: {
                                    Text(r.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                }.buttonStyle(.plain)
                                Spacer()
                                Text("\(r.kcal)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                                Button { swapping = SlotID(id: slot) } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14)).foregroundStyle(Theme.blue)
                                }.buttonStyle(.plain).padding(.leading, 4)
                                Button { store.logRecipe(r, slot: slot.lowercased()) } label: {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.primary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 9)
                            if i < slots.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { store.generatePlan() } label: { Label("Regenerate", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        for slot in slots { if let r = store.plannedRecipe(slot) { store.logRecipe(r, slot: slot.lowercased()) } }
                    } label: { Label("Log all", systemImage: "checklist").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 12)
            }
        }
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
                if let rating = FoodRating.rate(NutrientProfile(kcal: Double(r.kcal), protein: Double(r.protein), carbs: Double(r.carbs), fat: Double(r.fat)),
                                                plan: .from(programId: store.data.nutritionPlanId), planId: store.data.nutritionPlanId) {
                    RatingBadgeButton(rating: rating, title: r.name)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Pick a replacement recipe for one meal slot in the plan.
struct RecipeSwapSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: String

    private var options: [Recipe] {
        var list = RecipeCatalog.all.filter { $0.category == slot }
        if let plan = store.data.nutritionPlanId {
            list.sort { ($0.tags.contains(plan) ? 0 : 1) < ($1.tags.contains(plan) ? 0 : 1) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { r in
                        Button {
                            store.setPlannedMeal(r.id, slot: slot); dismiss()
                        } label: {
                            Card {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(r.color.opacity(0.18)).frame(width: 40, height: 40)
                                        Image(systemName: r.icon).font(.system(size: 17)).foregroundStyle(r.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                                        Text("\(r.kcal) kcal · \(r.minutes) min").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if store.plannedRecipe(slot)?.id == r.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                                    }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Swap \(slot)").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
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
