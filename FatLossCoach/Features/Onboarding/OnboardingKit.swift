import SwiftUI

// Reusable presentational pieces for the Livity-style guided onboarding, in the HUMANS dark theme.
// No green form chrome — full-bleed dark screens, one focus each, pinned CTA at the bottom.

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
        VStack(spacing: 0) {
            // Top bar: back · progress · close
            HStack(spacing: 12) {
                if showBack {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    }
                }
                ProgressBar(value: progress, height: 6)
                if canClose {
                    Button { onClose?() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(Theme.score(28)).foregroundStyle(Theme.text)
                        if let subtitle {
                            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(4)
                        }
                    }
                    content
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            // Pinned CTA
            Button(continueTitle) { onContinue() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!continueEnabled)
                .opacity(continueEnabled ? 1 : 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Theme.bg)
        }
        .background(Theme.bg)
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
    var headline: String
    var body_: String? = nil
    var features: [OBFeature] = []
    var primaryTitle: String = "Continue"
    var secondaryTitle: String? = nil
    var showBack: Bool = false
    var progress: Double? = nil
    var onBack: (() -> Void)? = nil
    var onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil
    @ViewBuilder var hero: Hero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showBack {
                    Button { onBack?() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    }
                }
                if let progress { ProgressBar(value: progress, height: 6) } else { Spacer() }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        if let eyebrow {
                            Text(eyebrow.uppercased()).font(.system(size: 12, weight: .bold)).kerning(1.2).foregroundStyle(Theme.primary)
                        }
                        Text(headline).font(Theme.score(32)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        if let body_ {
                            Text(body_).font(.system(size: 15)).foregroundStyle(Theme.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !features.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(features) { f in OBFeatureRow(f) }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                Button(primaryTitle) { onPrimary() }.buttonStyle(PrimaryButtonStyle())
                if let secondaryTitle {
                    Button(secondaryTitle) { (onSecondary ?? onPrimary)() }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            .background(Theme.bg)
        }
        .background(Theme.bg)
    }
}

// Convenience: intro with a simple icon-in-circle hero.
extension OnboardingIntro where Hero == OBIconHero {
    init(eyebrow: String? = nil, icon: String, tint: Color = Theme.primary,
         headline: String, body_: String? = nil, features: [OBFeature] = [],
         primaryTitle: String = "Continue", secondaryTitle: String? = nil,
         showBack: Bool = false, progress: Double? = nil,
         onBack: (() -> Void)? = nil, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil) {
        self.init(eyebrow: eyebrow, headline: headline, body_: body_, features: features,
                  primaryTitle: primaryTitle, secondaryTitle: secondaryTitle, showBack: showBack,
                  progress: progress, onBack: onBack, onPrimary: onPrimary, onSecondary: onSecondary,
                  hero: { OBIconHero(icon: icon, tint: tint) })
    }
}

struct OBIconHero: View {
    var icon: String
    var tint: Color = Theme.primary
    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14)).frame(width: 132, height: 132)
            Circle().stroke(tint.opacity(0.4), lineWidth: 1.5).frame(width: 132, height: 132)
            Image(systemName: icon).font(.system(size: 52, weight: .semibold)).foregroundStyle(tint)
        }
    }
}

struct OBFeatureRow: View {
    let f: OBFeature
    init(_ f: OBFeature) { self.f = f }
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(f.tint.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: f.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(f.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                Text(f.detail).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
        .padding(.vertical, 9).padding(.horizontal, 13)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Mini gauge (used in the Recovery/Strain/Sleep explainer)

struct OBMiniGauge: View {
    var value: Double        // 0...1 fill
    var display: String
    var label: String
    var tint: Color
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0.0, to: 0.75)
                    .stroke(Theme.border, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0.0, to: 0.75 * max(0, min(1, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: tint.opacity(0.6), radius: 6)
                Text(display).font(Theme.score(20)).foregroundStyle(Theme.text)
            }
            .frame(width: 84, height: 84)
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - "Building your plan" loader

/// Auto-advancing analysis screen. Cycles captions while a ring fills, then calls onDone.
struct OnboardingLoader: View {
    var name: String
    var onDone: () -> Void

    @State private var progress: Double = 0
    @State private var captionIndex = 0

    private var captions: [String] {
        ["Reading your answers…",
         "Estimating your maintenance burn…",
         "Sizing a deficit you can keep…",
         "Setting protein, carbs and fat…",
         "Shaping your training phases…",
         "Finishing your plan…"]
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 10).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: progress)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.primary.opacity(0.5), radius: 8)
                Text("\(Int(progress * 100))%").font(Theme.score(34)).foregroundStyle(Theme.text)
            }
            VStack(spacing: 8) {
                Text(name.isEmpty ? "Building your plan" : "Building \(name)'s plan")
                    .font(Theme.score(24)).foregroundStyle(Theme.text)
                Text(captions[min(captionIndex, captions.count - 1)])
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .transition(.opacity).id(captionIndex)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task {
            let steps = 60
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(55))
                withAnimation(.linear(duration: 0.05)) { progress = Double(i) / Double(steps) }
                let ci = Int(Double(i) / Double(steps) * Double(captions.count))
                if ci != captionIndex { withAnimation(.easeInOut(duration: 0.25)) { captionIndex = min(ci, captions.count - 1) } }
            }
            try? await Task.sleep(for: .milliseconds(250))
            onDone()
        }
    }
}
