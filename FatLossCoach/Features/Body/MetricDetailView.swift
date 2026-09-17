import SwiftUI

/// Generic KPI deep-dive: today's value (hero) + today's drivers + a 30-day trend.
/// Any Body card can present this with its own data, so every metric follows the same
/// "day on the card → trends in the detail" pattern.
struct MetricDetail: Identifiable {
    let id = UUID()
    let title: String
    let heroValue: String
    let heroSub: String
    let color: Color
    let fraction: Double            // 0…1 for the hero ring
    let rows: [(String, String)]    // today's drivers
    let bars: [TrendBar]            // 30-day series
    let trendMax: Double
    let trendSub: String
    let note: String?
}

struct MetricDetailView: View {
    let d: MetricDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topBar
                RingGauge(title: d.heroSub, value: d.heroValue, fraction: d.fraction,
                          color: d.color, size: 190, valueSize: 54)
                    .padding(.vertical, 10)
                if !d.rows.isEmpty {
                    DarkCard {
                        CardTitle("Today", "", chevron: false) {}
                        ForEach(Array(d.rows.enumerated()), id: \.offset) { i, r in
                            HStack {
                                Text(r.0).font(.system(size: 13)).foregroundStyle(W.muted)
                                Spacer()
                                Text(r.1).font(W.score(17)).foregroundStyle(W.text)
                            }
                            .padding(.vertical, 9)
                            if i < d.rows.count - 1 { Rectangle().fill(W.divider).frame(height: 1) }
                        }
                    }
                }
                DarkCard {
                    CardTitle("Last 30 days", d.trendSub, chevron: false) {}
                    if d.bars.allSatisfy({ $0.value <= 0 }) {
                        Text("No data yet").font(.system(size: 12)).foregroundStyle(W.muted)
                            .padding(.vertical, 20)
                    } else {
                        TrendBarChart(bars: d.bars, maxValue: d.trendMax)
                            .frame(height: 110).padding(.top, 4)
                    }
                    if let note = d.note {
                        Text(note).font(.system(size: 10)).foregroundStyle(W.muted.opacity(0.7)).padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(W.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(W.text)
                    .frame(width: 36, height: 36).background(W.card).clipShape(Circle())
            }
            Spacer()
            Text(d.title.uppercased()).font(W.label(13)).kerning(1.5).foregroundStyle(W.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }
}
