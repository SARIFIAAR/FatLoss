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

/// Quick logger — tap a size/drink to log its shots + caffeine.
struct CoffeeLogSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Bigger drinks = more shots. Tap to log — it counts toward your caffeine, not your calories.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 16)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(CoffeeCatalog.all) { p in
                        Button { store.logCoffee(p); dismiss() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: p.icon).font(.system(size: 16)).foregroundStyle(Theme.primary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(p.shots == p.shots.rounded() ? String(Int(p.shots)) : String(format: "%.1f", p.shots)) shot\(p.shots == 1 ? "" : "s") · \(Int(p.mg)) mg")
                                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Log coffee").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
