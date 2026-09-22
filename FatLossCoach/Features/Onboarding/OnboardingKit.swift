import SwiftUI

// Reusable presentational pieces for the Livity-class guided onboarding, in the HUMANS dark theme.
// Full-bleed dark screens, one focus each, an ambient hero bloom, pinned CTA. The gauges and
// showcase cards deliberately mirror the Body dashboard so onboarding reads as the same premium app.

// MARK: - Ambient background

/// A soft off-centre colour bloom over the dark bg — the "lit from within" look on every hero screen.
/// Radial, low-opacity, blurred; survives the whole appearance range because it sits on solid Theme.bg.
struct OBAmbient: View {
    var tint: Color = Theme.primary
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [tint.opacity(0.22), tint.opacity(0.05), .clear],
                           center: .init(x: 0.5, y: 0.28), startRadius: 4, endRadius: 360)
                .blur(radius: 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Progress rail

/// Slim segmented progress rail — reads as "step N of many" at a glance, not a raw fill bar.
struct OBProgressRail: View {
    var value: Double            // 0...1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.primary, Theme.primaryLight],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, min(1, value) * geo.size.width))
                    .shadow(color: Theme.primary.opacity(0.5), radius: 4)
                    .animation(.easeInOut(duration: 0.35), value: value)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Scaffold (question screens)

/// A single onboarding screen: slim top bar (progress + optional back), scrolling content, pinned CTA.
/// Used to host the questionnaire steps so every question reads like the rest of the app.
struct OnboardingScaffold<Content: View>: View {
    var progress: Double                 // 0...1, drives the top bar
    var title: String
    var subtitle: String? = nil
    var showBack: Bool
    var canClose: Bool = false
    var continueTitle: String = "Continue"
    var continueEnabled: Bool = true
    var onBack: () -> Void
    var onClose: (() -> Void)? = nil
    var onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            OBAmbient()
            VStack(spacing: 0) {
                // Top bar: back · progress · close
                HStack(spacing: 14) {
                    if showBack {
                        Button { onBack() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06), in: Circle())
                        }
                        .accessibilityLabel("Back")
                    }
                    OBProgressRail(value: progress)
                    if canClose {
                        Button { onClose?() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.muted)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06), in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(Theme.score(30)).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle {
                                Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.muted).lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)

                // Pinned CTA over a soft fade so content scrolls under it, not into it.
                OBFooter {
                    Button(continueTitle) { onContinue() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!continueEnabled)
                        .opacity(continueEnabled ? 1 : 0.45)
                        .animation(.easeInOut(duration: 0.2), value: continueEnabled)
                }
            }
        }
    }
}

/// Pinned bottom bar with a top gradient scrim so scrolling content dissolves under the CTA.
struct OBFooter<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg.opacity(0.9), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -24)
        )
    }
}

// MARK: - Narrative / explainer screen

struct OBFeature: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var detail: String
    var tint: Color = Theme.primary
}

/// A full-screen narrative beat: hero (icon or custom), headline, body, optional feature rows, one CTA.
/// Used for welcome, privacy, "how it works", the Recovery/Strain/Sleep pitch, and the value prop.
struct OnboardingIntro<Hero: View>: View {
    var eyebrow: String? = nil
    var eyebrowTint: Color = Theme.primary
    var headline: String
    var body_: String? = nil
    var features: [OBFeature] = []
    var showcase: AnyView? = nil
    var ambientTint: Color = Theme.primary
    var primaryTitle: String = "Continue"
    var secondaryTitle: String? = nil
    var showBack: Bool = false
    var progress: Double? = nil
    var onBack: (() -> Void)? = nil
    var onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil
    @ViewBuilder var hero: Hero

    var body: some View {
        ZStack {
            OBAmbient(tint: ambientTint)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    if showBack {
                        Button { onBack?() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06), in: Circle())
                        }
                        .accessibilityLabel("Back")
                    }
                    if let progress { OBProgressRail(value: progress) } else { Spacer() }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                            .padding(.bottom, 4)

                        VStack(alignment: .leading, spacing: 12) {
                            if let eyebrow {
                                Text(eyebrow.uppercased())
                                    .font(.system(size: 12, weight: .heavy)).kerning(1.4)
                                    .foregroundStyle(eyebrowTint)
                            }
                            Text(headline).font(Theme.score(34)).foregroundStyle(Theme.text)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let body_ {
                                Text(body_).font(.system(size: 16)).foregroundStyle(Theme.muted).lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let showcase { showcase }

                        if !features.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(features) { f in OBFeatureRow(f) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                OBFooter {
                    VStack(spacing: 4) {
                        Button(primaryTitle) { onPrimary() }.buttonStyle(PrimaryButtonStyle())
                        if let secondaryTitle {
                            Button(secondaryTitle) { (onSecondary ?? onPrimary)() }
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
                                .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }
}

// Convenience: intro with a simple icon-in-circle hero.
extension OnboardingIntro where Hero == OBIconHero {
    init(eyebrow: String? = nil, eyebrowTint: Color = Theme.primary, icon: String, tint: Color = Theme.primary,
         headline: String, body_: String? = nil, features: [OBFeature] = [], showcase: AnyView? = nil,
         primaryTitle: String = "Continue", secondaryTitle: String? = nil,
         showBack: Bool = false, progress: Double? = nil,
         onBack: (() -> Void)? = nil, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil) {
        self.init(eyebrow: eyebrow, eyebrowTint: eyebrowTint, headline: headline, body_: body_, features: features,
                  showcase: showcase, ambientTint: tint,
                  primaryTitle: primaryTitle, secondaryTitle: secondaryTitle, showBack: showBack,
                  progress: progress, onBack: onBack, onPrimary: onPrimary, onSecondary: onSecondary,
                  hero: { OBIconHero(icon: icon, tint: tint) })
    }
}

/// Glyph in a layered glass-lit disc — a lit hero mark, not a flat outline circle.
struct OBIconHero: View {
    var icon: String
    var tint: Color = Theme.primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16)).frame(width: 150, height: 150).blur(radius: 24)
            Circle()
                .fill(
                    RadialGradient(colors: [tint.opacity(0.30), tint.opacity(0.10)],
                                   center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 80)
                )
                .frame(width: 116, height: 116)
                .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1.5))
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .clear],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
            Image(systemName: icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.5), radius: 8)
        }
        .scaleEffect(pulse ? 1.03 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

struct OBFeatureRow: View {
    let f: OBFeature
    init(_ f: OBFeature) { self.f = f }
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(f.tint.opacity(0.16)).frame(width: 46, height: 46)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(f.tint.opacity(0.28), lineWidth: 1).frame(width: 46, height: 46)
                Image(systemName: f.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(f.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                Text(f.detail).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Showcase card (explainer "product demo" cards, à la Livity)

/// A labelled demo card used inside explainers: eyebrow row + freeform content, styled like a Body card.
struct OBShowcaseCard<Content: View>: View {
    var eyebrow: String
    var icon: String
    var tint: Color = Theme.primary
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
                Text(eyebrow.uppercased()).font(.system(size: 11, weight: .heavy)).kerning(1.2).foregroundStyle(tint)
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
                Circle().fill(tint.opacity(0.14)).frame(width: 180, height: 180)
                    .blur(radius: 80).offset(x: -100, y: -80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
    }
}

/// One legend dot + label + value, for the sleep/score breakdown rows.
struct OBStatChip: View {
    var color: Color
    var label: String
    var value: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.scoreS).foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Device chip (welcome screen)

struct OBDeviceChip: View {
    var icon: String
    var name: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(name).font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(Theme.text)
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Works with \(name)")
    }
}

// MARK: - Signature gauge (matches the Body dashboard's 270° arc)

/// The app's signature gauge — a 270° arc with the metric's colour and a soft glow, identical in
/// construction to `RingGauge` on the Body dashboard, so a score in onboarding reads as a real score.
struct OBMiniGauge: View {
    var value: Double        // 0...1 fill
    var display: String
    var label: String
    var tint: Color
    var size: CGFloat = 92

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: size * 0.09, lineCap: .round) }
    private func arc(_ f: Double) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: size / 2, y: size / 2),
                     radius: size / 2 - size * 0.05,
                     startAngle: .degrees(135),
                     endAngle: .degrees(135 + 270 * f), clockwise: false)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                arc(1).stroke(Color.white.opacity(0.08), style: stroke)
                arc(max(0.02, min(1, value)))
                    .stroke(AngularGradient(gradient: Gradient(colors: [tint.opacity(0.5), tint]),
                                            center: .center,
                                            startAngle: .degrees(135), endAngle: .degrees(135 + 270)),
                            style: stroke)
                    .shadow(color: tint.opacity(0.55), radius: 6)
                Text(display).font(Theme.score(size * 0.24)).foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            .frame(width: size, height: size)
            Text(label.uppercased()).font(.system(size: 10, weight: .heavy)).kerning(1.1).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(display)")
    }
}

// MARK: - "Building your plan" loader

/// Auto-advancing analysis screen. Cycles captions while a ring fills, then calls onDone.
struct OnboardingLoader: View {
    var name: String
    var onDone: () -> Void

    @State private var progress: Double = 0
    @State private var captionIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var captions: [String] {
        ["Reading your answers…",
         "Estimating your maintenance burn…",
         "Sizing a deficit you can keep…",
         "Setting protein, carbs and fat…",
         "Shaping your training phases…",
         "Finishing your plan…"]
    }

    var body: some View {
        ZStack {
            OBAmbient()
            VStack(spacing: 30) {
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 12).frame(width: 168, height: 168)
                    Circle().trim(from: 0, to: progress)
                        .stroke(AngularGradient(gradient: Gradient(colors: [Theme.primary.opacity(0.5), Theme.primaryLight]),
                                                center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 168, height: 168)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.primary.opacity(0.5), radius: 10)
                    Text("\(Int(progress * 100))%").font(Theme.score(38)).foregroundStyle(Theme.text)
                }
                VStack(spacing: 10) {
                    Text(name.isEmpty ? "Building your plan" : "Building \(name)'s plan")
                        .font(Theme.score(26)).foregroundStyle(Theme.text)
                    Text(captions[min(captionIndex, captions.count - 1)])
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                        .transition(.opacity).id(captionIndex)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your plan")
        .task {
            let steps = 60
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(55))
                withAnimation(.linear(duration: 0.05)) { progress = Double(i) / Double(steps) }
                let ci = Int(Double(i) / Double(steps) * Double(captions.count))
                if ci != captionIndex {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { captionIndex = min(ci, captions.count - 1) }
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
            onDone()
        }
    }
}

// MARK: - Text field

/// Dark, on-brand text field — replaces the light system `.roundedBorder` control across onboarding.
/// Supports single-line and growing multi-line (axis: .vertical + lines range).
struct OBTextField: View {
    @Binding var text: String
    var placeholder: String
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil
    var caps: TextInputAutocapitalization = .sentences

    var body: some View {
        Group {
            if axis == .vertical {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lines ?? 1...4)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textInputAutocapitalization(caps)
        .autocorrectionDisabled(false)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.text)
        .tint(Theme.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
