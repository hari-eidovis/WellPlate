import SwiftUI
import Vision
import VisionKit

@available(iOS 17, *)
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// Called exactly once per scan session when a barcode payload is detected.
    let onScan: (String) -> Void
    /// Called if the scanner becomes unavailable — permission denied, unsupported
    /// hardware, or a runtime camera failure. Message is user-facing.
    let onError: ((String) -> Void)?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.upce, .ean8, .ean13, .code128, .qr, .aztec, .pdf417])
            ],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Only start once — guard against repeated calls on every SwiftUI re-render.
        guard !context.coordinator.didStartScanning else { return }
        context.coordinator.didStartScanning = true
        print("[BarcodeScanner] startScanning() called — isSupported: \(DataScannerViewController.isSupported)")
        do {
            try uiViewController.startScanning()
            print("[BarcodeScanner] scanning started successfully")
        } catch let error as DataScannerViewController.ScanningUnavailable {
            print("[BarcodeScanner] startScanning() threw ScanningUnavailable: \(error)")
            context.coordinator.handleUnavailable(error)
        } catch {
            print("[BarcodeScanner] startScanning() threw unexpected error: \(error)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onError: ((String) -> Void)?
        /// Prevents duplicate onScan callbacks from multiple didAdd delegate calls.
        private var hasFired = false
        /// Guards against calling startScanning() more than once across re-renders.
        var didStartScanning = false

        init(onScan: @escaping (String) -> Void, onError: ((String) -> Void)?) {
            self.onScan = onScan
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            print("[BarcodeScanner] didAdd items: \(addedItems.count), hasFired: \(hasFired)")
            guard !hasFired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item {
                    let payload = barcode.payloadStringValue
                    print("[BarcodeScanner] barcode item found — payload: \(payload ?? "nil")")
                    if let payload, !payload.isEmpty {
                        hasFired = true
                        dataScanner.stopScanning()
                        print("[BarcodeScanner] firing onScan with payload: \(payload)")
                        onScan(payload)
                        return
                    }
                }
            }
        }

        // Runtime camera failure after scanning has started (e.g. interrupted by a call).
        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            handleUnavailable(error)
        }

        /// Shared handler for both startup throws and runtime delegate errors.
        func handleUnavailable(_ error: DataScannerViewController.ScanningUnavailable) {
            print("[BarcodeScanner] ⚠️ scanner unavailable: \(error)")
            switch error {
            case .cameraRestricted:
                onError?("Camera access is required. Enable it in Settings.")
            case .unsupported:
                onError?("Barcode scanning is not supported on this device.")
            @unknown default:
                onError?("Camera unavailable.")
            }
        }
    }
}
