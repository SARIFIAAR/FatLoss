import SwiftUI

// MARK: - Ariana meal program UI (Nutrition tab)
//
// Entry card → ProgramView (Breakfast / Lunch / Dinner) → breakfast recipe list → recipe detail.
// Data: `MealProgram.ariana` (Models/MealProgram.swift). Dark theme via `Theme`.
// Logging reuses the diary path: `store.addMeal(recipe.mealEntry(on:))`.

// MARK: Entry-point card (shown in the Nutrition diary)

struct ArianaProgramCard: View {
    // `-ariana 1` (QA/screenshots) auto-opens the program sheet on launch; no production effect.
    @State private var open = UserDefaults.standard.bool(forKey: "ariana")
    private let program = MealProgram.ariana

    var body: some View {
        Button { open = true } label: {
            VStack(spacing: 0) {
                // Hero studio image from the first breakfast recipe.
                if let hero = program.recipes(in: .breakfast).first {
                    Color.clear
                        .frame(height: 150)
                        .overlay {
                            Image(hero.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .overlay(alignment: .topLeading) {
                            Text("MEAL PROGRAM")
                                .font(.system(size: 10, weight: .bold)).kerning(1.2)
                                .foregroundStyle(.white)
                                .padding(.vertical, 5).padding(.horizontal, 10)
                                .background(.black.opacity(0.35), in: Capsule())
                                .padding(12)
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        Text("Breakfast · Lunch · Dinner")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) {
            ArianaProgramNav(program: program)
                .preferredColorScheme(.dark)
        }
    }
}

/// Program navigation stack with optional QA deep-links (`-arianaList breakfast`, `-arianaRecipe ariana-b01`).
private struct ArianaProgramNav: View {
    let program: MealProgram
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ArianaProgramView(program: program)
                .navigationDestination(for: MealCategory.self) { c in
                    ArianaCategoryListView(program: program, category: c)
                }
                .navigationDestination(for: MealProgram.Recipe.self) { r in
                    ArianaRecipeDetailView(recipe: r)
                }
        }
        .onAppear {
            let d = UserDefaults.standard
            if let cat = d.string(forKey: "arianaList"), let c = MealCategory(rawValue: cat) {
                path.append(c)
            }
            if let rid = d.string(forKey: "arianaRecipe"),
               let r = program.recipes.first(where: { $0.id == rid }) {
                path.append(r.category)
                path.append(r)
            }
        }
    }
}

// MARK: Program overview — three category rows

struct ArianaProgramView: View {
    let program: MealProgram
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let hero = program.recipes(in: .breakfast).first {
                    Color.clear
                        .frame(height: 180)
                        .overlay {
                            Image(hero.imageName).resizable().aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text(program.name)
                    .font(Theme.score(26)).foregroundStyle(Theme.text)
                Text(program.blurb)
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(MealCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Program").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }

    // Every category navigates the same way: row → generic recipe list → detail. An empty category
    // (Lunch/Dinner today) opens the same list and shows its own empty state. No per-category branch.
    private func categoryRow(_ category: MealCategory) -> some View {
        let count = program.recipes(in: category).count
        return NavigationLink {
            ArianaCategoryListView(program: program, category: category)
        } label: {
            Card {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.primary.opacity(count > 0 ? 0.18 : 0.08)).frame(width: 44, height: 44)
                        Image(systemName: icon(category))
                            .font(.system(size: 18))
                            .foregroundStyle(count > 0 ? Theme.primary : Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text(count > 0 ? "\(count) recipe\(count == 1 ? "" : "s")" : "Coming soon")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func icon(_ c: MealCategory) -> String {
        switch c {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        }
    }
}

// MARK: Category recipe list (breakfast)

struct ArianaCategoryListView: View {
    let program: MealProgram
    let category: MealCategory

    private var recipes: [MealProgram.Recipe] { program.recipes(in: category) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if recipes.isEmpty {
                    emptyState
                } else {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            ArianaRecipeDetailView(recipe: recipe)
                        } label: {
                            recipeRow(recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 26)).foregroundStyle(Theme.muted)
                Text("No recipes here yet — coming soon")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                Text("\(category.title) bowls are on the way. Breakfast is ready to explore now.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func recipeRow(_ r: MealProgram.Recipe) -> some View {
        Card(padding: 10) {
            HStack(spacing: 12) {
                Color.clear
                    .frame(width: 64, height: 64)
                    .overlay { Image(r.imageName).resizable().aspectRatio(contentMode: .fill) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title)
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text("\(Int(r.nutrition.kcal)) kcal")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text("P \(Int(r.nutrition.protein)) · C \(Int(r.nutrition.carbs)) · F \(Int(r.nutrition.fat))")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: Recipe detail

struct ArianaRecipeDetailView: View {
    @Environment(Store.self) private var store
    let recipe: MealProgram.Recipe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Large studio header
                Color.clear
                    .frame(height: 240)
                    .overlay { Image(recipe.imageName).resizable().aspectRatio(contentMode: .fill) }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(Theme.score(24)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Serves \(recipe.serves) · \(recipe.timeMin) min · \(recipe.type)")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }

                logButton

                section("Ingredients") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.primary).frame(width: 5, height: 5).padding(.top, 7)
                                Text(item).font(.system(size: 14)).foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                section("Method") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(recipe.method.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Color(hex: 0x101518))
                                    .frame(width: 24, height: 24)
                                    .background(Theme.primary, in: Circle())
                                Text(step).font(.system(size: 14)).foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                nutritionCard

                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 15)).foregroundStyle(Theme.primary).padding(.top, 1)
                        Text(recipe.note)
                            .font(.system(size: 14)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(recipe.category.title).navigationBarTitleDisplayMode(.inline)
    }

    private var logButton: some View {
        Button {
            store.addMeal(recipe.mealEntry(on: store.today))
        } label: {
            Label("Log to today's \(recipe.category.title.lowercased())", systemImage: "plus.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var nutritionCard: some View {
        let n = recipe.nutrition
        return Card {
            SectionTitle("Nutrition · per serving")
            HStack(spacing: 10) {
                stat("\(Int(n.kcal))", "kcal")
                stat("\(Int(n.protein)) g", "protein")
                stat("\(Int(n.carbs)) g", "carbs")
                stat("\(Int(n.fat)) g", "fat")
            }
            HStack(spacing: 10) {
                stat("\(Int(n.fibre)) g", "fibre")
                stat("\(Int(n.sugar)) g", "sugar")
            }
            .padding(.top, 10)
            if n.isEstimate {
                Text("Estimate from standard food databases — a guide, not a lab measurement. Assumes semi-skimmed milk; \"to taste\" extras not counted.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        StatBox {
            Text(value).font(Theme.scoreM).foregroundStyle(Theme.text)
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            SectionTitle(title)
            content()
        }
    }
}
