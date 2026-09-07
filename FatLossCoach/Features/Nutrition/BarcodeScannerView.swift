import SwiftUI
import VisionKit

/// Live barcode reader (EAN/UPC) using VisionKit. Calls `onCode` once with the first barcode seen.
struct BarcodeScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScanner { code in
                        dismiss()
                        onCode(code)
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Point the camera at the barcode on the packaging")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .padding(.vertical, 10).padding(.horizontal, 16)
                            .background(.black.opacity(0.6)).clipShape(Capsule())
                            .padding(.bottom, 30)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "barcode.viewfinder").font(.system(size: 44)).foregroundStyle(Theme.muted)
                        Text("Barcode scanning needs the camera on a real iPhone.")
                            .font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .padding(30)
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .itf14])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let code = b.payloadStringValue, !code.isEmpty {
                    fired = true
                    scanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}
