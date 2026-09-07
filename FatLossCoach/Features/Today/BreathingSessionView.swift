import SwiftUI
import AVFoundation
import UIKit

/// Drives one guided breathing session: ready countdown → inhale / hold / exhale / hold cycles until the
/// slot's time or cycle count is used up. Spoken cues (AVSpeechSynthesizer), ambient music and haptics.
@Observable
final class BreathingSession {
    enum State { case intro, countdown, running, paused, finished }
    enum Phase {
        case inhale, hold, exhale, rest
        var label: String {
            switch self {
            case .inhale: return "breathe in"
            case .hold, .rest: return "hold"
            case .exhale: return "breathe out"
            }
        }
        var spoken: String {
            switch self {
            case .inhale: return "Breathe in"
            case .hold, .rest: return "Hold"
            case .exhale: return "Breathe out"
            }
        }
    }

    let slot: BreathingSlot
    /// The non-zero phases of this technique, in order — one side of the shape each.
    let phases: [(phase: Phase, seconds: Int)]
    var state: State = .intro
    var countdown = 3
    var phaseIndex = 0
    var phaseRemaining = 0
    /// Wall-clock start of the current phase; the view derives smooth dot position from it.
    var phaseStart = Date()
    var pausedAt: Date?
    var remaining: Int
    var cyclesDone = 0
    var finishedEarly = false

    var voiceOn: Bool {
        didSet { UserDefaults.standard.set(voiceOn, forKey: "breathVoice"); if !voiceOn { synth.stopSpeaking(at: .immediate) } }
    }
    var musicOn: Bool {
        didSet {
            UserDefaults.standard.set(musicOn, forKey: "breathMusic")
            if musicOn, state == .running || state == .countdown { startMusic() } else if !musicOn { stopMusic() }
        }
    }

    private let synth = AVSpeechSynthesizer()
    private var music: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private let tap = UIImpactFeedbackGenerator(style: .medium)

    init(slot: BreathingSlot) {
        self.slot = slot
        self.remaining = slot.totalSeconds
        self.voiceOn = UserDefaults.standard.object(forKey: "breathVoice") as? Bool ?? true
        self.musicOn = UserDefaults.standard.object(forKey: "breathMusic") as? Bool ?? true
        self.phases = [(Phase.inhale, slot.inhale), (.hold, slot.hold1), (.exhale, slot.exhale), (.rest, slot.hold2)].filter { $0.1 > 0 }
        self.phaseRemaining = phases.first?.seconds ?? 0
    }

    var phase: Phase { phases[phaseIndex].phase }
    var phaseTotal: Int { phases[phaseIndex].seconds }
    var completed: Bool { state == .finished && !finishedEarly }

    /// 0…1 through the current phase at wall-clock `now` (frozen while paused).
    func phaseProgress(at now: Date) -> Double {
        guard state == .running || state == .paused, phaseTotal > 0 else { return 0 }
        let end = pausedAt ?? now
        return min(1, max(0, end.timeIntervalSince(phaseStart) / Double(phaseTotal)))
    }

    func start() {
        guard state == .intro else { return }
        configureAudio()
        UIApplication.shared.isIdleTimerDisabled = true
        state = .countdown
        countdown = 3
        if musicOn { startMusic() }
        task = Task { [weak self] in await self?.run() }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        pausedAt = Date()
        synth.pauseSpeaking(at: .immediate)
        music?.setVolume(0.15, fadeDuration: 0.6)
        tap.impactOccurred(intensity: 0.6)
    }

    func resume() {
        guard state == .paused, let p = pausedAt else { return }
        phaseStart = phaseStart.addingTimeInterval(Date().timeIntervalSince(p))
        pausedAt = nil
        state = .running
        music?.setVolume(0.5, fadeDuration: 0.6)
        say(phase.spoken)
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
            music?.setVolume(0, fadeDuration: 4)
            Task { [weak self] in try? await Task.sleep(for: .seconds(4)); self?.stopMusic() }
        }
    }

    private func run() async {
        while countdown > 0 {
            if Task.isCancelled { return }
            say(countdown == 3 ? "Get comfortable. Starting in 3" : "\(countdown)")
            try? await Task.sleep(for: .seconds(1))
            countdown -= 1
        }
        say("Relax your shoulders. Let's begin.")
        try? await Task.sleep(for: .seconds(2))
        if Task.isCancelled { return }
        state = .running

        outer: while !Task.isCancelled {
            for i in phases.indices {
                phaseIndex = i
                phaseRemaining = phases[i].seconds
                phaseStart = Date()
                tap.impactOccurred()
                say(phases[i].phase.spoken)
                for _ in 0..<phases[i].seconds {
                    while state == .paused { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
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
        // .playback so cues are heard with the silent switch on; duck other apps' audio rather than stopping it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startMusic() {
        if music == nil, let url = Bundle.main.url(forResource: "breathing_ambient", withExtension: "m4a") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.prepareToPlay()
        }
        guard let music, !music.isPlaying else { return }
        music.volume = 0
        music.play()
        music.setVolume(0.5, fadeDuration: 3)
    }

    private func stopMusic() {
        music?.stop()
        music = nil
    }

    deinit {
        task?.cancel()
        synth.stopSpeaking(at: .immediate)
        music?.stop()
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
            OceanBackground().ignoresSafeArea()
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
                    Text(slot.guide).font(.system(size: 15)).foregroundStyle(.white.opacity(0.88)).lineSpacing(5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW THE GUIDE WORKS").font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(Theme.accent)
                        tip(shapeIcon, "A dot travels along the \(shapeName) — one side per step. Breathe in as it climbs, out as it descends, hold on the flat sides.")
                        tip("speaker.wave.2.fill", "A voice says each step and the phone taps gently at every change, so you can close your eyes.")
                        tip("checkmark.circle.fill", "Finishing ticks the session off your schedule and your breathing habit.")
                    }
                    .padding(14)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(20)
            }
            VStack(spacing: 8) {
                Toggle(isOn: Binding(get: { session.voiceOn }, set: { session.voiceOn = $0 })) {
                    Label("Voice guidance", systemImage: "speaker.wave.2.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.primaryLight)
                Toggle(isOn: Binding(get: { session.musicOn }, set: { session.musicOn = $0 })) {
                    Label("Calming music", systemImage: "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.primaryLight)
                Button { session.start() } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .padding(20)
            .background(.black.opacity(0.25))
        }
    }

    private var shapeName: String {
        switch session.phases.count { case 4: return "square"; case 3: return "triangle"; default: return "circle" }
    }
    private var shapeIcon: String {
        switch session.phases.count { case 4: return "square"; case 3: return "triangle"; default: return "circle" }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(.white.opacity(0.14)).clipShape(Capsule())
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineSpacing(3)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { roundIcon("xmark") }
            Spacer()
            if session.state != .intro {
                Button { session.musicOn.toggle() } label: { roundIcon(session.musicOn ? "music.note" : "speaker.slash") }
                Button { session.voiceOn.toggle() } label: { roundIcon(session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill") }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .frame(width: 38, height: 38).background(.white.opacity(0.16)).clipShape(Circle())
    }

    // MARK: session

    private var active: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 6) {
                Text(slot.name).font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                Text(slot.patternLabel).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 8)
            Spacer()
            BreathShape(session: session)
                .frame(width: 320, height: 320)
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
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
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
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).lineSpacing(4)
                .padding(.horizontal, 30)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(20)
        }
        .onAppear { if session.completed || session.cyclesDone >= 3 { store.markBreathingDone(slot.name) } }
    }
}

// MARK: - Breath shape (triangle / square / circle with a travelling dot)

/// One side per phase: a dot moves along the shape continuously — up on inhale, across on hold, down on
/// exhale — so nothing ever jumps back. Two-phase patterns use a circle (up the right, down the left).
struct BreathShape: View {
    let session: BreathingSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: session.state != .running)) { ctx in
            let n = session.phases.count
            let p = session.state == .countdown ? 0 : session.phaseProgress(at: ctx.date)
            let idx = session.state == .countdown ? 0 : session.phaseIndex
            GeometryReader { geo in
                let rect = geo.frame(in: .local).insetBy(dx: 40, dy: 40)
                let path = shapePath(sides: n, in: rect)
                let dot = position(sides: n, in: rect, side: idx, t: p)
                ZStack {
                    path.stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)).blur(radius: 6)
                    path.stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    // Side labels
                    ForEach(0..<n, id: \.self) { i in
                        let lab = sideLabel(sides: n, in: rect, side: i)
                        Text("\(session.phases[i].phase.label) · \(session.phases[i].seconds)s")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(i == idx && session.state != .countdown ? Theme.accent : .white.opacity(0.75))
                            .fixedSize()
                            .rotationEffect(lab.angle)
                            .position(lab.point)
                    }
                    // Travelling dot
                    Circle().fill(.white).frame(width: 30, height: 30)
                        .shadow(color: .white.opacity(0.9), radius: 14)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 26)
                        .position(dot)
                    // Centre text
                    VStack(spacing: 2) {
                        if session.state == .countdown {
                            Text(session.countdown > 0 ? "get ready" : "relax…").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                            Text(session.countdown > 0 ? "\(session.countdown)" : "begin").font(.system(size: session.countdown > 0 ? 44 : 30, weight: .black)).foregroundStyle(.white)
                        } else {
                            Text(session.state == .paused ? "paused" : session.phase.label)
                                .font(.system(size: n == 3 ? 22 : 26, weight: .bold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 8)
                            Text("\(session.phaseRemaining)").font(.system(size: 34, weight: .black)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                                .contentTransition(.numericText())
                        }
                    }
                    .position(x: rect.midX, y: n == 3 ? rect.midY + rect.height * 0.12 : rect.midY)
                }
            }
        }
    }

    private func vertices(sides: Int, in r: CGRect) -> [CGPoint] {
        switch sides {
        case 3: return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)]
        default: return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)]
        }
    }

    private func shapePath(sides: Int, in r: CGRect) -> Path {
        if sides <= 2 { return Path(ellipseIn: r) }
        var p = Path()
        let v = vertices(sides: sides, in: r)
        p.move(to: v[0]); for pt in v.dropFirst() { p.addLine(to: pt) }; p.closeSubpath()
        return p
    }

    /// Point on side `side` at fraction `t` (0 = start vertex, 1 = next vertex). Circle: side 0 is the right
    /// half from bottom to top, side 1 the left half from top to bottom.
    private func position(sides: Int, in r: CGRect, side: Int, t: Double) -> CGPoint {
        if sides <= 2 {
            let angle = (side == 0 ? Double.pi / 2 - t * Double.pi : -Double.pi / 2 - t * Double.pi)
            return CGPoint(x: r.midX + cos(angle) * r.width / 2, y: r.midY + sin(angle) * r.height / 2)
        }
        let v = vertices(sides: sides, in: r)
        let a = v[side % v.count], b = v[(side + 1) % v.count]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Where a side's label sits (just outside the side's midpoint) and how it is rotated to run along it.
    private func sideLabel(sides: Int, in r: CGRect, side: Int) -> (point: CGPoint, angle: Angle) {
        let gap: CGFloat = 20
        if sides <= 2 {
            return side == 0 ? (CGPoint(x: r.maxX + gap, y: r.midY), .degrees(90)) : (CGPoint(x: r.minX - gap, y: r.midY), .degrees(-90))
        }
        let v = vertices(sides: sides, in: r)
        let a = v[side % v.count], b = v[(side + 1) % v.count]
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        // outward normal = away from the centre of the shape
        var nx = -dy / len, ny = dx / len
        if (mid.x + nx - r.midX) * (mid.x - r.midX) + (mid.y + ny - r.midY) * (mid.y - r.midY) < (mid.x - r.midX) * (mid.x - r.midX) + (mid.y - r.midY) * (mid.y - r.midY) {
            nx = -nx; ny = -ny
        }
        var deg = atan2(dy, dx) * 180 / .pi
        if deg > 90 { deg -= 180 } else if deg < -90 { deg += 180 }   // keep text upright
        return (CGPoint(x: mid.x + nx * gap, y: mid.y + ny * gap), .degrees(deg))
    }
}

// MARK: - Ocean background

private extension OceanBackground {
    static func wave(index fw: Double, time t: Double, size: CGSize) -> Path {
        var path = Path()
        let baseY: Double = size.height * (0.55 + fw * 0.12)
        let speed: Double = 0.5 + fw * 0.15
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: Double = 0
        while x <= size.width {
            let a: Double = 14 * sin(x / 70 + t * speed + fw)
            let b: Double = 8 * sin(x / 31 - t * 0.35 + fw * 2)
            path.addLine(to: CGPoint(x: x, y: baseY + a + b))
            x += 6
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Living background: deep teal gradient, slow drifting light patches and soft rolling waves — no assets.
struct OceanBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0B3B4A), Color(hex: 0x0E5E5C), Color(hex: 0x134E4A), Color(hex: 0x0A2A2E)],
                               startPoint: .top, endPoint: .bottom)
                Canvas { g, size in
                    // Caustic light patches
                    for i in 0..<5 {
                        let fi = Double(i)
                        let x = size.width * (0.5 + 0.42 * sin(t * 0.07 + fi * 1.7))
                        let y = size.height * (0.5 + 0.38 * cos(t * 0.05 + fi * 2.3))
                        let rad = size.width * (0.35 + 0.1 * sin(t * 0.11 + fi))
                        let rect = CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)
                        g.fill(Path(ellipseIn: rect),
                               with: .radialGradient(Gradient(colors: [Color(hex: 0x5EEAD4).opacity(0.16), .clear]),
                                                     center: CGPoint(x: x, y: y), startRadius: 0, endRadius: rad))
                    }
                    // Rolling waves
                    for w in 0..<4 {
                        let fw = Double(w)
                        let path = Self.wave(index: fw, time: t, size: size)
                        g.fill(path, with: .color(.white.opacity(0.035 + fw * 0.01)))
                    }
                }
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
