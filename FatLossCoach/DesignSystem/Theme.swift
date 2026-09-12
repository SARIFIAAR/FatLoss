import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// Single dark palette shared with the Body dashboard (`W`) so every tab reads as one app.
/// The app is dark-only; `adaptive` remains for any stragglers but both sides match.
enum Theme {
    static let primary      = Color(hex: 0x42B883)   // calm emerald — CTAs, selected state
    static let primaryLight = Color(hex: 0x43CB00)
    static let accent       = Color(hex: 0x42B883)
    static let orange       = Color(hex: 0xF0C930)
    static let red          = Color(hex: 0xFF0026)
    static let blue         = Color(hex: 0x0093E7)

    static let bg     = Color(hex: 0x101518)
    static let card   = Color(hex: 0x1A2227)
    static let card2  = Color(hex: 0x232E35)         // inset boxes / tracks
    static let text   = Color.white
    static let muted  = Color(hex: 0x7A8B94)
    static let border = Color(hex: 0x232E35)

    /// Big numerals — heavy condensed, same face as the Body gauges.
    static func score(_ size: CGFloat) -> Font {
        Font(UIFont.systemFont(ofSize: size, weight: .heavy, width: .condensed))
    }

    // Type scale (matches the Body screen) — use these, not ad-hoc heavy sizes.
    static let titleL = score(24)    // screen & card titles, 4-up target numbers
    static let scoreL = score(34)    // hero numbers (gauge centres, big stats)
    static let scoreM = score(17)    // stat / row values
    static let scoreS = score(14)    // compact values, chips
}

enum Fmt {
    /// 105 -> "105", 105.4 -> "105.4"
    static func num(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
    static func parse(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

enum Readiness {
    // Zone colors match the Body dashboard: green / yellow / red.
    static func color(_ s: Int) -> Color {
        s >= 67 ? Color(hex: 0x43CB00) : s >= 34 ? Theme.orange : Theme.red
    }
    static func label(_ s: Int?) -> String {
        guard let s else { return "Connect Apple Health" }
        return s >= 80 ? "Excellent — Push Hard 💪"
             : s >= 65 ? "Good — Ready to Train"
             : s >= 45 ? "Moderate — Listen to Body"
             : "Low — Prioritise Rest 🛌"
    }
}

// MARK: - Layout building blocks

/// Green header + scrolling content, mirroring the web app's `.top-bar` + `.screen`.
struct Screen<Content: View>: View {
    let subtitle: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    TopBar(subtitle: subtitle, title: title, topInset: geo.safeAreaInsets.top)
                    VStack(spacing: 14) { content }
                        .padding(16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(edges: .top)
        }
        .background(Theme.bg)
    }
}

struct TopBar: View {
    let subtitle: String
    let title: String
    var topInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(subtitle.uppercased())
                .font(.system(size: 11, weight: .bold)).kerning(1.2)
                .foregroundStyle(Theme.muted)
            Text(title).font(Theme.score(26)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, topInset + 12)
        .padding(.bottom, 10)
        .background(Theme.bg)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(Theme.muted)
            .padding(.bottom, 10)
    }
}

struct StatBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 3) { content }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProgressBar: View {
    var value: Double            // 0...1
    var height: CGFloat = 10
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.accent)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(fill)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .animation(.easeOut(duration: 0.4), value: value)
            }
        }
        .frame(height: height)
    }
}

/// Visual-only check circle (use inside a row that is itself a Button).
struct CheckMark: View {
    var done: Bool
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().fill(done ? Theme.primary : Color.clear)
            Circle().stroke(done ? Theme.primary : Theme.muted, lineWidth: 2)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x101518))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: done)
    }
}

/// Tappable check circle.
struct CheckCircle: View {
    var done: Bool
    var size: CGFloat = 26
    var action: () -> Void
    var body: some View {
        Button(action: action) { CheckMark(done: done, size: size) }
            .buttonStyle(.plain)
    }
}

struct NumField: View {
    let placeholder: String
    @Binding var text: String
    var decimal = true
    var width: CGFloat? = 64

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border, lineWidth: 2))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        // Vibrant fills need dark text for contrast; deep fills keep white.
        let darkText = color == Theme.primary || color == Theme.orange
        configuration.label
            .font(.system(size: compact ? 13 : 16, weight: .bold))
            .foregroundStyle(darkText ? Color(hex: 0x101518) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 9 : 14)
            .padding(.horizontal, 12)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(outlined ? color : .white)
            .padding(.vertical, 9)
            .padding(.horizontal, 20)
            .background(outlined ? Theme.bg : color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(outlined ? Theme.accent : Color.clear, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Toast

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(hex: 0x101518))
            .padding(.vertical, 10)
            .padding(.horizontal, 22)
            .background(Theme.primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(.top, 8)
    }
}

// MARK: - Value entry sheet (weight / waist)

struct LogValueSheet: View {
    let title: String
    let placeholder: String
    /// Return true to dismiss.
    let onSave: (Double) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(Theme.scoreM).foregroundStyle(Theme.text)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(14)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(focused ? Theme.accent : Theme.border, lineWidth: 2))
                .focused($focused)
                .submitLabel(.done)
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Save") {
                    guard let v = Fmt.parse(text) else { return }
                    if onSave(v) { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(Theme.card)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}
