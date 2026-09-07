import SwiftUI
import AVFoundation
import UIKit

/// Drives one guided breathing session: ready countdown → inhale / hold / exhale / hold cycles until the
/// slot's time or cycle count is used up. Spoken cues (AVSpeechSynthesizer) and haptics on each phase.
@Observable
final class BreathingSession {
    enum State { case intro, countdown, running, paused, finished }
    enum Phase {
        case inhale, hold, exhale, rest
        var label: String {
            switch self {
            case .inhale: return "Breathe in"
            case .hold, .rest: return "Hold"
            case .exhale: return "Breathe out"
            }
        }
    }

    let slot: BreathingSlot
    var state: State = .intro
    var countdown = 3
    var phase: Phase = .inhale
    var phaseTotal = 4
    var phaseRemaining = 4
    var remaining: Int
    var cyclesDone = 0
    var voiceOn: Bool {
        didSet { UserDefaults.standard.set(voiceOn, forKey: "breathVoice"); if !voiceOn { synth.stopSpeaking(at: .immediate) } }
    }

    private let synth = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?
    private let tap = UIImpactFeedbackGenerator(style: .medium)

    init(slot: BreathingSlot) {
        self.slot = slot
        self.remaining = slot.totalSeconds
        self.voiceOn = UserDefaults.standard.object(forKey: "breathVoice") as? Bool ?? true
        phaseTotal = slot.inhale
        phaseRemaining = slot.inhale
    }

    var finishedEarly = false
    var completed: Bool { state == .finished && !finishedEarly }
    var elapsedMinutes: Int { max(1, Int(((Double(slot.totalSeconds - remaining)) / 60).rounded(.up))) }

    /// Circle scale target for the current phase: big on inhale/hold, small on exhale/rest.
    var scale: CGFloat { (phase == .inhale || phase == .hold) ? 1.0 : 0.62 }

    func start() {
        guard state == .intro else { return }
        configureAudio()
        UIApplication.shared.isIdleTimerDisabled = true
        state = .countdown
        countdown = 3
        task = Task { [weak self] in await self?.run() }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        synth.pauseSpeaking(at: .immediate)
        tap.impactOccurred(intensity: 0.6)
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        say(phase.label)
        tap.impactOccurred(intensity: 0.6)
    }

    func stop() {
        if state == .running || state == .paused || state == .countdown { finishedEarly = true }
        finish()
    }

    private func finish() {
        task?.cancel()
        task = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if state != .finished {
            state = .finished
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            say(finishedEarly ? "Session ended. Take a moment to relax." : "Well done. Your session is complete. Notice how calm your body feels.")
        }
    }

    private func run() async {
        // Ready countdown
        while countdown > 0 {
            if Task.isCancelled { return }
            say(countdown == 3 ? "Get comfortable. Starting in 3" : "\(countdown)")
            try? await Task.sleep(for: .seconds(1))
            countdown -= 1
        }
        state = .running
        say("Relax your shoulders. Let's begin.")
        try? await Task.sleep(for: .seconds(2))

        let phases: [(Phase, Int)] = [(.inhale, slot.inhale), (.hold, slot.hold1), (.exhale, slot.exhale), (.rest, slot.hold2)].filter { $0.1 > 0 }
        outer: while !Task.isCancelled {
            for (p, secs) in phases {
                phase = p
                phaseTotal = secs
                phaseRemaining = secs
                tap.impactOccurred()
                say(p.label)
                for _ in 0..<secs {
                    while state == .paused { try? await Task.sleep(for: .milliseconds(200)); if Task.isCancelled { return } }
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    phaseRemaining -= 1
                    remaining -= 1
                }
            }
            cyclesDone += 1
            if let c = slot.cycles, cyclesDone >= c { break outer }
            if slot.cycles == nil && remaining <= 0 { break outer }
        }
        finish()
    }

    private func say(_ text: String) {
        guard voiceOn else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.42
        u.pitchMultiplier = 0.95
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    private func configureAudio() {
        // .playback so cues are heard with the silent switch on; duck music instead of stopping it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    deinit {
        task?.cancel()
        synth.stopSpeaking(at: .immediate)
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

struct BreathingSessionView: View {
    @State private var session: BreathingSession
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(slot: BreathingSlot) { _session = State(initialValue: BreathingSession(slot: slot)) }

    private var slot: BreathingSlot { session.slot }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E1A14), Color(hex: 0x1B4332)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            switch session.state {
            case .intro: intro
            case .countdown, .running, .paused: active
            case .finished: done
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if UserDefaults.standard.bool(forKey: "breathingStart") { session.start() } }
        .onDisappear { session.stop() }
    }

    // MARK: intro

    private var intro: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Text(slot.icon).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(slot.name).font(.system(size: 24, weight: .heavy)).foregroundStyle(.white)
                            Text(slot.time).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    HStack(spacing: 8) {
                        pill(slot.patternLabel)
                        pill(slot.cycles.map { "\($0) cycles" } ?? "\(slot.minutes) min")
                    }
                    Text(slot.guide).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)).lineSpacing(5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW THE GUIDE WORKS").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(Theme.accent)
                        tip("circle.dashed", "The circle grows while you breathe in and shrinks while you breathe out. Match its pace.")
                        tip("speaker.wave.2.fill", "A voice says each step. A gentle tap on the phone marks every change.")
                        tip("checkmark.circle.fill", "Finishing ticks the session off your schedule and your breathing habit.")
                    }
                    .padding(14)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Toggle(isOn: Binding(get: { session.voiceOn }, set: { session.voiceOn = $0 })) {
                    Label("Voice guidance", systemImage: "speaker.wave.2.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.primaryLight)
                Button { session.start() } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(.white.opacity(0.12)).clipShape(Capsule())
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.white.opacity(0.12)).clipShape(Circle())
            }
            Spacer()
            if session.state != .intro {
                Button { session.voiceOn.toggle() } label: {
                    Image(systemName: session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.white.opacity(0.12)).clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    // MARK: session

    private var active: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 6) {
                Text(slot.name).font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                Text(slot.patternLabel).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            }
            .padding(.top, 8)
            Spacer()
            BreathCircle(session: session)
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 24) {
                    stat(value: timeString(session.remaining), label: slot.cycles == nil ? "remaining" : "elapsed")
                    stat(value: "\(session.cyclesDone)\(slot.cycles.map { "/\($0)" } ?? "")", label: "cycles")
                }
                HStack(spacing: 12) {
                    Button {
                        if session.state == .paused { session.resume() } else { session.pause() }
                    } label: {
                        Label(session.state == .paused ? "Resume" : "Pause", systemImage: session.state == .paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(session.state == .countdown)
                    Button { session.stop() } label: { Label("End", systemImage: "stop.fill") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
    }

    private func timeString(_ s: Int) -> String {
        let v = slot.cycles == nil ? max(0, s) : slot.totalSeconds - max(0, s)
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(minWidth: 90)
    }

    // MARK: done

    private var done: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(session.completed ? "🌿" : "🌬️").font(.system(size: 64))
            Text(session.completed ? "Session complete" : "Session ended").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
            Text(session.completed
                 ? "\(slot.name) · \(session.cyclesDone) cycles. Notice how much calmer you feel — this is the state to make food decisions in."
                 : "You did \(session.cyclesDone) cycle\(session.cyclesDone == 1 ? "" : "s"). Even a short session counts — come back when you can.")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).lineSpacing(4)
                .padding(.horizontal, 30)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(20)
        }
        .onAppear { if session.completed || session.cyclesDone >= 3 { store.markBreathingDone(slot.name) } }
    }
}

/// The breathing circle: scales with the phase (grow on inhale, shrink on exhale), a ring that fills over the
/// phase, the phase name and a seconds countdown in the middle.
struct BreathCircle: View {
    let session: BreathingSession

    private var progress: Double {
        guard session.phaseTotal > 0 else { return 0 }
        return 1 - Double(session.phaseRemaining) / Double(session.phaseTotal)
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.10)).frame(width: 300, height: 300)
            Circle()
                .fill(RadialGradient(colors: [Theme.primaryLight.opacity(0.9), Theme.primary.opacity(0.6)], center: .center, startRadius: 20, endRadius: 150))
                .frame(width: 260, height: 260)
                .scaleEffect(session.state == .countdown ? 0.62 : session.scale)
                .shadow(color: Theme.accent.opacity(0.35), radius: 40)
                .animation(.easeInOut(duration: Double(session.phaseTotal)), value: session.scale)
            Circle().stroke(.white.opacity(0.12), lineWidth: 10).frame(width: 290, height: 290)
            Circle()
                .trim(from: 0, to: session.state == .countdown ? 0 : progress)
                .stroke(AngularGradient(colors: [Theme.accent, .white, Theme.accent], center: .center), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 290, height: 290)
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 4) {
                if session.state == .countdown {
                    Text("Get ready").font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    Text("\(session.countdown)").font(.system(size: 54, weight: .black)).foregroundStyle(.white)
                } else {
                    Text(session.state == .paused ? "Paused" : session.phase.label)
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    Text("\(session.phaseRemaining)").font(.system(size: 54, weight: .black)).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}
