import SwiftUI
import PhotosUI

/// Unified multimodal "Log with AI" composer — one place to describe a meal by text, voice or photo,
/// then Send routes to the same AI analysis path. Mirrors Lifesum's single AI-logging flow.
struct AIMealComposer: View {
    @Environment(\.dismiss) private var dismiss
    let onText: (String) -> Void
    let onImage: (UIImage) -> Void
    /// A scanned barcode resolved to a packaged product — folded into the same result surface as
    /// text/voice/photo. Optional so existing callers keep working.
    var onBarcode: ((FoodSearch.Food) -> Void)? = nil

    @State private var text = ""
    @State private var voice = VoiceInput()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showBarcode = false
    @State private var barcodeBusy = false
    @State private var barcodeError: String?
    @State private var barcodeDB = FoodSearch()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").foregroundStyle(Theme.primary)
                            Text("Tell me what you ate").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text)
                        }
                        Text("Type it, say it, or snap a photo — I'll estimate the calories and macros.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)

                        // Text field with inline mic
                        HStack(alignment: .top, spacing: 8) {
                            TextField("e.g. two eggs, toast and a flat white", text: $text, axis: .vertical)
                                .font(.system(size: 15)).foregroundStyle(Theme.text)
                                .focused($focused).lineLimit(1...5)
                            Button {
                                if voice.isRecording { voice.stop() } else { Task { await voice.requestAuth(); voice.start() } }
                            } label: {
                                Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.system(size: 26)).foregroundStyle(voice.isRecording ? Theme.red : Theme.primary)
                            }.buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: voice.transcript) { _, t in if !t.isEmpty { text = t } }

                        if voice.isRecording {
                            HStack(spacing: 6) {
                                Circle().fill(Theme.red).frame(width: 8, height: 8)
                                Text("Listening…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }

                        // Photo attach
                        HStack(spacing: 10) {
                            Button { showCamera = true } label: {
                                Label("Photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(SecondaryButtonStyle())
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("Library", systemImage: "photo.on.rectangle")
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent, lineWidth: 2))
                            }
                        }

                        // Barcode as one more inline input, feeding the same result surface.
                        if onBarcode != nil {
                            Button { barcodeError = nil; showBarcode = true } label: {
                                Label("Scan a barcode", systemImage: "barcode.viewfinder")
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.blue)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.blue, lineWidth: 2))
                            }
                            if barcodeBusy {
                                HStack(spacing: 8) {
                                    ProgressView().tint(Theme.blue)
                                    Text("Looking up product…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                            if let barcodeError {
                                Text(barcodeError).font(.system(size: 12)).foregroundStyle(Theme.red)
                            }
                        }
                    }
                    .padding(16)
                }
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    voice.stop()
                    if !t.isEmpty { onText(t); dismiss() }
                } label: {
                    Text("Send to AI").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Log with AI").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { voice.stop(); dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        voice.stop(); onImage(img); dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in showCamera = false; if let img { voice.stop(); onImage(img); dismiss() } }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showBarcode) {
                BarcodeScannerView { code in Task { await lookupBarcode(code) } }
                    .ignoresSafeArea()
            }
            .onDisappear { voice.stop() }
        }
    }

    /// Resolve a scanned barcode to a product, then hand it to the shared result surface.
    private func lookupBarcode(_ code: String) async {
        barcodeBusy = true; barcodeError = nil
        defer { barcodeBusy = false }
        do {
            let food = try await barcodeDB.barcode(code)
            voice.stop(); onBarcode?(food); dismiss()
        } catch {
            barcodeError = "Couldn't find that product. Try again or describe it above."
        }
    }
}
