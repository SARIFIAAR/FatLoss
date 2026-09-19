import WidgetKit
import SwiftUI

// MARK: - Shared payload (mirrors HumansWidgetData in the app target, by field name)

private let appGroupID = "group.com.MyFatLossCoach.app"
private let widgetFile = "humans-widget.json"

struct BodyKPIs: Codable {
    var score: Int?
    var scoreLabel: String = "—"
    var recovery: Int?
    var recoveryLabel: String
    var strain: Double
    var strainLabel: String
    var sleepPct: Int?
    var sleepHours: Double?
    var battery: Int?
    var stress: Int?
    var updated: Date

    static let placeholder = BodyKPIs(
        score: 78, scoreLabel: "Strong", recovery: 72, recoveryLabel: "Balanced", strain: 11.4, strainLabel: "Moderate",
        sleepPct: 88, sleepHours: 7.4, battery: 64, stress: 30, updated: .now)

    static func load() -> BodyKPIs {
        guard
            let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent(widgetFile),
            let data = try? Data(contentsOf: url)
        else { return .placeholder }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(BodyKPIs.self, from: data)) ?? .placeholder
    }
}

// MARK: - Palette (matches the HUMANS dark theme)

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let hBG      = Color(hex: 0x101518)
    static let hCard    = Color(hex: 0x1A2227)
    static let hGreen   = Color(hex: 0x42B883)
    static let hAmber   = Color(hex: 0xF2B33D)
    static let hRed     = Color(hex: 0xE5533C)
    static let hBlue    = Color(hex: 0x4CA9E8)
    static let hText2   = Color.white.opacity(0.55)
}

private func recoveryColor(_ s: Int?) -> Color {
    guard let s = s else { return .hText2 }
    return s >= 67 ? .hGreen : s >= 34 ? .hAmber : .hRed
}

// MARK: - Timeline

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, kpis: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, kpis: context.isPreview ? .placeholder : BodyKPIs.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now, kpis: BodyKPIs.load())
        // The app reloads timelines whenever data changes; this is just a periodic safety refresh.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let kpis: BodyKPIs
}

// MARK: - Views

/// A thin progress ring with a centred value.
private struct Ring: View {
    var value: Double        // 0…1
    var color: Color
    var big: String
    var small: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(big).font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(small).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.hText2)
            }
        }
    }
}

/// One compact metric tile for the medium layout.
private struct Tile: View {
    var label: String
    var value: String
    var unit: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(Color.hText2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.hText2)
            }
            Capsule().fill(color).frame(width: 26, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SmallView: View {
    let k: BodyKPIs
    var body: some View {
        VStack(spacing: 8) {
            Ring(value: Double(k.recovery ?? 0) / 100,
                 color: recoveryColor(k.recovery),
                 big: k.recovery.map(String.init) ?? "—",
                 small: "RECOVERY")
                .frame(width: 78, height: 78)
            Text(k.recoveryLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(recoveryColor(k.recovery))
        }
    }
}

struct MediumView: View {
    let k: BodyKPIs
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                Ring(value: Double(k.recovery ?? 0) / 100,
                     color: recoveryColor(k.recovery),
                     big: k.recovery.map(String.init) ?? "—",
                     small: "RECOVERY")
                    .frame(width: 84, height: 84)
                Text(k.recoveryLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(recoveryColor(k.recovery))
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Tile(label: "Strain", value: String(format: "%.1f", k.strain), unit: "/21", color: .hBlue)
                    Tile(label: "Battery", value: k.battery.map(String.init) ?? "—", unit: "%", color: .hGreen)
                }
                HStack(spacing: 10) {
                    Tile(label: "Sleep", value: k.sleepPct.map(String.init) ?? "—", unit: "%", color: .hGreen)
                    Tile(label: "Stress", value: k.stress.map(String.init) ?? "—", unit: "", color: .hAmber)
                }
            }
        }
    }
}

struct HumansWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(k: entry.kpis).containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text("HUMANS \(entry.kpis.score.map(String.init) ?? "–") · \(entry.kpis.scoreLabel)")
        case .accessoryRectangular:
            AccessoryRectView(k: entry.kpis).containerBackground(.clear, for: .widget)
        case .systemSmall:
            SmallView(k: entry.kpis).containerBackground(for: .widget) { bg }
        default:
            MediumView(k: entry.kpis).containerBackground(for: .widget) { bg }
        }
    }
    private var bg: some View {
        LinearGradient(colors: [.hCard, .hBG], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Lock Screen circular gauge — the HUMANS Score.
struct AccessoryCircularView: View {
    let k: BodyKPIs
    var body: some View {
        Gauge(value: Double(k.score ?? 0), in: 0...100) {
            Text("HS")
        } currentValueLabel: {
            Text("\(k.score ?? 0)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

/// Lock Screen rectangular — score + recovery/sleep line.
struct AccessoryRectView: View {
    let k: BodyKPIs
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HUMANS \(k.score.map(String.init) ?? "–") · \(k.scoreLabel)").font(.system(size: 14, weight: .bold))
            Text("Rec \(k.recovery.map(String.init) ?? "–") · Sleep \(k.sleepPct.map { "\($0)%" } ?? "–") · Strain \(String(format: "%.1f", k.strain))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widgets

struct HumansBodyWidget: Widget {
    let kind = "HumansBodyWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HumansWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("HUMANS Score")
        .description("Your daily HUMANS Score, recovery, strain, sleep and body battery.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct HumansWidgetBundle: WidgetBundle {
    var body: some Widget {
        HumansBodyWidget()
    }
}
