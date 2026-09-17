import SwiftUI

/// Temporary A/B/C design bake-off: the same Recovery data rendered in three visual directions,
/// shown at the top of the Body tab so we can compare live on device. Remove once a direction is chosen.
struct DesignLabSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DESIGN LAB — SAME DATA, 3 LOOKS")
                .font(.system(size: 11, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.muted)

            tag("A — Livity-plus (premium dark)")
            RecoveryCardA()

            tag("B — Editorial (Apple Fitness+)")
            RecoveryCardB()

            tag("C — Depth / glass (futuristic)")
            RecoveryCardC()

            Divider().overlay(Theme.border).padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.primary)
    }
}

// Shared demo data so all three cards show identical numbers.
private enum Demo {
    static let score = 72
    static let label = "Recovered"
    static let hrv = "64", rhr = "52", sleep = "88"
    static let trend: [Double] = [0.52, 0.63, 0.71, 0.66, 0.82, 0.75, 0.72]
    static var color: Color { Readiness.color(score) }
    static var frac: Double { Double(score) / 100 }
}

// MARK: - A · Livity-plus premium dark

private struct RecoveryCardA: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Demo.color)
                Text("RECOVERY").font(.system(size: 12, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Demo.score)").font(Theme.scoreM).foregroundStyle(Theme.text)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 16) {
                LabRing(frac: Demo.frac, color: Demo.color, value: "\(Demo.score)", unit: "%")
                    .frame(width: 78, height: 78)
                VStack(spacing: 8) {
                    statRow("HRV", Demo.hrv, "ms")
                    statRow("Resting HR", Demo.rhr, "bpm")
                    statRow("Sleep", Demo.sleep, "%")
                }
            }
            HStack(spacing: 10) {
                Text(Demo.label).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Demo.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Demo.color.opacity(0.15), in: Capsule())
                Spacer()
                Sparkbars(values: Demo.trend, color: Demo.color).frame(width: 96, height: 24)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }

    private func statRow(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(Theme.scoreM).foregroundStyle(Theme.text)
            Text(unit).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - B · Editorial (Apple Fitness+)

private struct RecoveryCardB: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("RECOVERY").font(.system(size: 12, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.muted)
            Text("\(Demo.score)").font(Theme.score(64)).foregroundStyle(Theme.text)
            Capsule().fill(Demo.color).frame(width: 54, height: 4)
            Text(Demo.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Demo.color)
            HStack(spacing: 6) {
                editorialStat("HRV", "\(Demo.hrv)")
                dot
                editorialStat("RHR", "\(Demo.rhr)")
                dot
                editorialStat("Sleep", "\(Demo.sleep)%")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }

    private var dot: some View {
        Circle().fill(Theme.muted).frame(width: 3, height: 3)
    }
    private func editorialStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }
}

// MARK: - C · Depth / glass

private struct RecoveryCardC: View {
    var body: some View {
        HStack(spacing: 16) {
            LabRing(frac: Demo.frac, color: Demo.color, value: "\(Demo.score)", unit: "%", glow: true)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text("RECOVERY").font(.system(size: 12, weight: .bold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Text(Demo.label).font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                HStack(spacing: 12) {
                    glassStat("HRV", Demo.hrv)
                    glassStat("RHR", Demo.rhr)
                    glassStat("Sleep", "\(Demo.sleep)%")
                }
            }
            Spacer()
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [Demo.color.opacity(0.28), .clear],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(Demo.color.opacity(0.35)).frame(width: 130, height: 130)
                    .blur(radius: 60).offset(x: -70, y: -20)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func glassStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Shared components

private struct LabRing: View {
    var frac: Double
    var color: Color
    var value: String
    var unit: String
    var glow = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, frac)))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? 8 : 0)
            VStack(spacing: 0) {
                Text(value).font(Theme.score(26)).foregroundStyle(Theme.text)
                Text(unit).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct Sparkbars: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let n = max(values.count, 1)
            let gap: CGFloat = 3
            let w = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.85))
                        .frame(width: w, height: max(3, geo.size.height * CGFloat(v)))
                }
            }
        }
    }
}
