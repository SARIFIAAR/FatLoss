import SwiftUI

struct NutritionView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let g = store.data.goals
        let ml = store.waterToday
        let pct = min(Double(ml) / Double(g.waterGoal), 1)
        Screen(subtitle: "Fuel your fat loss", title: "Nutrition 🥗") {
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
                SectionTitle("Meal Plan")
                VStack(spacing: 0) {
                    ForEach(Array(Plan.meals.enumerated()), id: \.element.id) { i, m in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                Text(m.time).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            Text(m.kcal).font(.system(size: 13)).foregroundStyle(Theme.muted)
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

            Card {
                SectionTitle("Daily Macro Targets")
                VStack(spacing: 10) {
                    MacroBar(name: "🥩 Protein", value: "\(g.protein)g", fraction: 0.65, color: Theme.primary)
                    MacroBar(name: "🍚 Carbs", value: "\(g.carbs)g", fraction: 0.55, color: Theme.orange)
                    MacroBar(name: "🥑 Fat", value: "\(g.fat)g", fraction: 0.42, color: Theme.blue)
                }
                Text("Total: \(g.kcal.formatted()) kcal · \(g.deficit) kcal deficit daily")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .padding(.top, 10)
            }
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
