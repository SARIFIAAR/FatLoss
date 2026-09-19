import SwiftUI
import Speech
import AVFoundation

/// On-device speech-to-text for hands-free meal logging. Transcribes a spoken meal description,
/// then the caller feeds the text into the same AI text-analysis path as "Type it in".
@Observable
@MainActor
final class VoiceInput {
    var transcript = ""
    var isRecording = false
    var authorized = false
    var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuth() async {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        authorized = (status == .authorized)
        if !authorized { error = "Speech recognition permission is off. Enable it in Settings." }
    }

    func start() {
        guard !isRecording else { return }
        transcript = ""; error = nil
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition unavailable."; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
                req?.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if err != nil || (result?.isFinal ?? false) { self.stop() }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Sheet: hold-to-talk (or tap start/stop), shows the live transcript, then "Log this".
struct VoiceMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var voice = VoiceInput()
    let onText: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Text(voice.transcript.isEmpty ? "Tell me what you ate" : voice.transcript)
                    .font(.system(size: voice.transcript.isEmpty ? 20 : 22, weight: .bold))
                    .foregroundStyle(voice.transcript.isEmpty ? Theme.muted : Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: 120)

                if let e = voice.error {
                    Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                Spacer()

                Button {
                    if voice.isRecording { voice.stop() } else { voice.start() }
                } label: {
                    ZStack {
                        Circle().fill(voice.isRecording ? Theme.red : Theme.primary).frame(width: 84, height: 84)
                            .shadow(color: (voice.isRecording ? Theme.red : Theme.primary).opacity(0.6), radius: voice.isRecording ? 16 : 6)
                        Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32)).foregroundStyle(Color(hex: 0x101518))
                    }
                }
                .buttonStyle(.plain)
                Text(voice.isRecording ? "Listening… tap to stop" : "Tap to speak")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)

                Button {
                    let t = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    voice.stop()
                    if !t.isEmpty { onText(t) }
                    dismiss()
                } label: {
                    Text("Log this").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(voice.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .background(Theme.bg)
            .navigationTitle("Say your meal").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { voice.stop(); dismiss() } } }
            .task { await voice.requestAuth() }
            .onDisappear { voice.stop() }
        }
    }
}
