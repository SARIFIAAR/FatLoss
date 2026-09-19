import SwiftUI

/// Scan two products and compare their nutrition side by side (per 100 g). Lifesum "Barcode Compare".
struct BarcodeCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var db = FoodSearch()
    @State private var left: FoodSearch.Food?
    @State private var right: FoodSearch.Food?
    @State private var scanning: Side?
    @State private var busy = false
    @State private var error: String?

    enum Side { case left, right }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        slot(left, side: .left)
                        slot(right, side: .right)
                    }
                    if busy {
                        HStack(spacing: 8) { ProgressView().tint(Theme.primary); Text("Looking up product…").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                    }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.red) }

                    if let l = left, let r = right {
                        Card {
                            Text("PER 100 g").font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted).padding(.bottom, 4)
                            compareRow("Calories", l.per100.kcal, r.per100.kcal, "kcal", lowerIsBetter: true)
                            compareRow("Protein", l.per100.protein, r.per100.protein, "g", lowerIsBetter: false)
                            compareRow("Carbs", l.per100.carbs, r.per100.carbs, "g", lowerIsBetter: true)
                            compareRow("Fat", l.per100.fat, r.per100.fat, "g", lowerIsBetter: true)
                        }
                    } else {
                        Text("Scan two products to compare them.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 20)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Barcode Compare").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(item: $scanning) { side in
                BarcodeScannerView { code in
                    scanning = nil
                    Task { await lookup(code, into: side) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func slot(_ food: FoodSearch.Food?, side: Side) -> some View {
        Button { scanning = side } label: {
            VStack(spacing: 8) {
                Image(systemName: food == nil ? "barcode.viewfinder" : "checkmark.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(food == nil ? Theme.muted : Theme.primary)
                Text(food?.name ?? (side == .left ? "Scan product A" : "Scan product B"))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center).lineLimit(2)
                if let food { Text("\(Int(food.per100.kcal.rounded())) kcal / 100 g").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func compareRow(_ label: String, _ a: Double, _ b: Double, _ unit: String, lowerIsBetter: Bool) -> some View {
        let aWins = lowerIsBetter ? a < b : a > b
        let bWins = lowerIsBetter ? b < a : b > a
        return HStack {
            Text("\(Int(a.rounded()))").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(aWins ? Theme.primary : Theme.text).frame(width: 60, alignment: .leading)
            Spacer()
            Text("\(label) (\(unit))").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
            Text("\(Int(b.rounded()))").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(bWins ? Theme.primary : Theme.text).frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private func lookup(_ code: String, into side: Side) async {
        busy = true; error = nil
        do {
            let food = try await db.barcode(code)
            if side == .left { left = food } else { right = food }
        } catch { self.error = "Couldn't find that product." }
        busy = false
    }
}

extension BarcodeCompareView.Side: Identifiable { var id: Int { self == .left ? 0 : 1 } }
