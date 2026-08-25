import SwiftUI
import AVFoundation
import UIKit

/// Bildschirmfüllender Kamera-Sucher mit Barcode-Erkennung.
///
/// - Erkennt QR + gängige 1D/2D-Barcodes via `AVCaptureMetadataOutput`.
/// - Bei Erkennung: haptisches Feedback, kurzes Einfrieren des Suchers,
///   danach exakt 1 Sekunde Cooldown ohne weitere Scan-Verarbeitung.
struct ScannerView: UIViewRepresentable {

    /// Wird bei jeder (nicht im Cooldown befindlichen) Erkennung aufgerufen — auf dem MainActor.
    var onScan: (String) -> Void
    /// Steuert Start/Stop der Capture-Session (App aktiv/inaktiv).
    var isActive: Bool
    /// Ändert sich der Wert, wird der Scan-Cooldown sofort zurückgesetzt
    /// (Schnellstart via Deep-Link / App Intent).
    var resetToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        context.coordinator.configure(previewView: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.setActive(isActive)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            context.coordinator.resetCooldown()
        }
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    // MARK: - Preview-View

    /// UIView, deren Backing-Layer direkt der `AVCaptureVideoPreviewLayer` ist.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {

        var onScan: (String) -> Void

        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "de.timehrenfried.qr-keyboard-scanner.capture")
        private var isConfigured = false
        private var isRunning = false
        private weak var previewView: PreviewView?

        /// Bis zu diesem Zeitpunkt werden erkannte Codes ignoriert (1-s-Cooldown).
        private var cooldownUntil = Date.distantPast
        private let feedbackGenerator = UINotificationFeedbackGenerator()

        /// Alle unterstützten Symbologien laut Aufgabenstellung.
        private static let desiredTypes: [AVMetadataObject.ObjectType] = [
            .qr, .ean8, .ean13, .code128, .code39, .code93,
            .pdf417, .dataMatrix, .aztec, .interleaved2of5, .itf14, .upce
        ]

        /// Zuletzt verarbeiteter Reset-Token (siehe `ScannerView.resetToken`).
        var resetToken = 0

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        /// Hebt Cooldown und Preview-Freeze sofort auf (MainActor/Main-Thread).
        func resetCooldown() {
            cooldownUntil = .distantPast
            previewView?.videoPreviewLayer.connection?.isEnabled = true
        }

        func configure(previewView: PreviewView) {
            self.previewView = previewView
            previewView.videoPreviewLayer.session = session
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
            }
        }

        func setActive(_ active: Bool) {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configureSessionIfNeeded()
                if active, !self.isRunning, self.isConfigured {
                    self.session.startRunning()
                    self.isRunning = true
                } else if !active, self.isRunning {
                    self.session.stopRunning()
                    self.isRunning = false
                }
            }
        }

        /// Läuft auf der sessionQueue.
        private func configureSessionIfNeeded() {
            guard !isConfigured,
                  AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            session.beginConfiguration()
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = Self.desiredTypes.filter {
                output.availableMetadataObjectTypes.contains($0)
            }
            session.commitConfiguration()
            isConfigured = true
        }

        // MARK: AVCaptureMetadataOutputObjectsDelegate (Delegate-Queue: main)

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let now = Date()
            guard now >= cooldownUntil else { return }
            guard let object = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.stringValue?.isEmpty == false }),
                  let text = object.stringValue else { return }

            // Exakt 1 Sekunde Cooldown: keine weitere Scan-Verarbeitung.
            cooldownUntil = now.addingTimeInterval(1.0)

            // Haptisches Feedback + Sucher kurz visuell einfrieren.
            feedbackGenerator.notificationOccurred(.success)
            freezePreview(for: 1.0)

            onScan(text)
        }

        /// Friert das Vorschaubild ein, indem die Preview-Connection kurz
        /// deaktiviert wird; nach `duration` ist der Sucher wieder scharf.
        private func freezePreview(for duration: TimeInterval) {
            guard let previewLayer = previewView?.videoPreviewLayer,
                  let connection = previewLayer.connection else { return }
            connection.isEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                connection.isEnabled = true
            }
        }
    }
}

// MARK: - Kamera-Berechtigung

/// Hinweis-Screen, wenn die Kamera-Berechtigung verweigert wurde.
struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Kein Kamerazugriff")
                .font(.title2.bold())
            Text("Zum Scannen von Codes benötigt die App Zugriff auf die Kamera. Bitte erlaube den Zugriff in den Einstellungen.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Einstellungen öffnen", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
