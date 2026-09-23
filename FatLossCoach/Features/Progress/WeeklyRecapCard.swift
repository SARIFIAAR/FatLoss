import SwiftUI

/// "This week" recap card on the Progress tab. Read-only aggregation of the last 7 days with a
/// week-over-week delta vs the prior 7. Honest: a metric with no data shows "—" and no delta arrow.
/// Weekly cadence — reconciled with, not a duplicate of, the daily Life Score (see WeeklyRecap).
struct WeeklyRecapCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        let recap = store.weeklyRecap()
        Card {
            HStack {
                SectionTitle("This Week")
                Spacer()
                Text("vs last 7 days").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 10)
            }
            if !recap.hasAnyData {
                Text("Log meals, water, habits or connect Apple Health to see your weekly recap here.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            } else {
                let chunked = rows(recap)
                VStack(spacing: 10) {
                    ForEach(Array(chunked.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            ForEach(row) { m in MetricTile(metric: m) }
                            // Pad an odd last row so tiles keep their width.
                            if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
                Text("Averages over the last 7 completed days. Rows with no data are hidden.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 10)
            }
        }
    }

    /// Only tiles that have this-week data, chunked two-per-row.
    private func rows(_ recap: WeeklyRecap) -> [[WeeklyRecap.Metric]] {
        let shown = recap.metrics.filter { $0.hasThisWeek }
        return stride(from: 0, to: shown.count, by: 2).map { Array(shown[$0..<min($0 + 2, shown.count)]) }
    }
}

private struct MetricTile: View {
    let metric: WeeklyRecap.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: metric.systemImage).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Text(metric.title.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(metric.thisWeekText).font(Theme.score(22)).foregroundStyle(Theme.text)
            if let deltaText = metric.deltaText {
                Text(deltaText).font(.system(size: 10, weight: .semibold)).foregroundStyle(deltaColor)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("no prior week").font(.system(size: 10)).foregroundStyle(Theme.muted.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var deltaColor: Color {
        switch metric.deltaIsGood {
        case .some(true): return Theme.primary
        case .some(false): return Theme.red
        case .none: return Theme.muted            // no change
        }
    }
}
