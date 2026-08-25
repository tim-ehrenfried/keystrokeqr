import SwiftUI
import AVFoundation
import UIKit

/// Bildschirmfüllender Kamera-Sucher mit Barcode-Erkennung.
///
/// - Erkennt QR + gängige 1D/2D-Barcodes via `AVCaptureMetadataOutput`.
/// - Nutzt die beste virtuelle Rückkamera (Triple → DualWide → Dual → Wide),
///   damit iOS Linsen (inkl. Makro) automatisch umschaltet.
/// - Kontinuierlicher Autofokus mit Nahbereichs-Präferenz, Tap-to-Focus,
///   Pinch-to-Zoom.
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
    /// Meldet (auf dem Main-Thread), ob die Capture-Session tatsächlich läuft —
    /// solange nicht, zeigt ContentView einen dunklen Lade-Zustand.
    var onRunningChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        context.coordinator.configure(previewView: view)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onRunningChanged = onRunningChanged
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
        var onRunningChanged: ((Bool) -> Void)?
        /// Zuletzt verarbeiteter Reset-Token (siehe `ScannerView.resetToken`).
        var resetToken = 0

        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "de.timehrenfried.qr-keyboard-scanner.capture")
        private var isConfigured = false
        private var isRunning = false
        private weak var previewView: PreviewView?
        private var videoDevice: AVCaptureDevice?
        private var subjectAreaObserver: NSObjectProtocol?

        /// Bis zu diesem Zeitpunkt werden erkannte Codes ignoriert (1-s-Cooldown).
        private var cooldownUntil = Date.distantPast
        private let feedbackGenerator = UINotificationFeedbackGenerator()
        /// Zoom-Faktor zu Beginn einer Pinch-Geste.
        private var pinchStartZoom: CGFloat = 1.0

        /// Alle unterstützten Symbologien laut Aufgabenstellung.
        private static let desiredTypes: [AVMetadataObject.ObjectType] = [
            .qr, .ean8, .ean13, .code128, .code39, .code93,
            .pdf417, .dataMatrix, .aztec, .interleaved2of5, .itf14, .upce
        ]

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        deinit {
            if let subjectAreaObserver {
                NotificationCenter.default.removeObserver(subjectAreaObserver)
            }
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
                    self.notifyRunning(true)
                } else if !active, self.isRunning {
                    self.session.stopRunning()
                    self.isRunning = false
                    self.notifyRunning(false)
                }
            }
        }

        /// Hebt Cooldown und Preview-Freeze sofort auf (Main-Thread).
        func resetCooldown() {
            cooldownUntil = .distantPast
            previewView?.videoPreviewLayer.connection?.isEnabled = true
        }

        private func notifyRunning(_ running: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.onRunningChanged?(running)
            }
        }

        // MARK: Session-Konfiguration (läuft auf der sessionQueue)

        /// Beste Rückkamera: virtuelle Devices zuerst — sie schalten Linsen
        /// automatisch um (inkl. Makro-Umschaltung bei nahen Codes).
        private static func bestBackCamera() -> AVCaptureDevice? {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInWideAngleCamera
                ],
                mediaType: .video,
                position: .back
            )
            return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
        }

        private func configureSessionIfNeeded() {
            guard !isConfigured,
                  AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let device = Self.bestBackCamera(),
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

            videoDevice = device
            configureDevice(device)
            isConfigured = true
        }

        /// Initialer Zoom + Fokus-/Belichtungs-Setup.
        private func configureDevice(_ device: AVCaptureDevice) {
            do {
                try device.lockForConfiguration()

                // Virtuelle Devices starten sonst im Ultraweitwinkel: der erste
                // Switch-Over-Faktor entspricht 1x der Weitwinkel-Linse.
                if let firstSwitchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                    device.videoZoomFactor = CGFloat(truncating: firstSwitchOver)
                } else {
                    device.videoZoomFactor = 1.0
                }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near // QR-Codes sind nah
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                // Ohne Lock bleibt die Default-Konfiguration aktiv — Scannen geht trotzdem.
            }

            subjectAreaObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureDeviceSubjectAreaDidChange,
                object: device,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async { self.resetFocusToCenter() }
            }
        }

        /// Nach Motivwechsel: Fokus/Belichtung zurück auf kontinuierlich + Mitte.
        private func resetFocusToCenter() {
            guard let device = videoDevice else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = center
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = center
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }

        // MARK: Tap-to-Focus

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewView else { return }
            let layerPoint = gesture.location(in: previewView)
            let devicePoint = previewView.videoPreviewLayer
                .captureDevicePointConverted(fromLayerPoint: layerPoint)
            showFocusIndicator(at: layerPoint)
            sessionQueue.async { [weak self] in
                self?.focus(at: devicePoint)
            }
        }

        /// Läuft auf der sessionQueue.
        private func focus(at devicePoint: CGPoint) {
            guard let device = videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                // Subject-Area-Monitoring setzt später wieder auf kontinuierlich zurück.
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch { }
        }

        /// Kleine gelbe Fokus-Anzeige am Tippunkt (Main-Thread).
        private func showFocusIndicator(at point: CGPoint) {
            guard let previewView else { return }
            let size: CGFloat = 72
            let indicator = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            indicator.center = point
            indicator.backgroundColor = .clear
            indicator.layer.borderColor = UIColor.systemYellow.cgColor
            indicator.layer.borderWidth = 1.5
            indicator.layer.cornerRadius = 8
            indicator.isUserInteractionEnabled = false
            previewView.addSubview(indicator)

            indicator.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
            UIView.animate(withDuration: 0.18, animations: {
                indicator.transform = .identity
            }, completion: { _ in
                UIView.animate(withDuration: 0.25, delay: 0.5, options: [], animations: {
                    indicator.alpha = 0
                }, completion: { _ in
                    indicator.removeFromSuperview()
                })
            })
        }

        // MARK: Pinch-to-Zoom

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let device = videoDevice else { return }
            switch gesture.state {
            case .began:
                pinchStartZoom = device.videoZoomFactor
            case .changed:
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                let minZoom = device.minAvailableVideoZoomFactor
                let target = min(max(pinchStartZoom * gesture.scale, minZoom), maxZoom)
                sessionQueue.async { [weak self] in
                    guard let device = self?.videoDevice else { return }
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = target
                        device.unlockForConfiguration()
                    } catch { }
                }
            default:
                break
            }
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

/// Hinweis-Screen, wenn die Kamera-Berechtigung verweigert wurde (dunkel).
struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            Text("Kein Kamerazugriff")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Zum Scannen von Codes benötigt die App Zugriff auf die Kamera. Bitte erlaube den Zugriff in den Einstellungen.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Einstellungen öffnen", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
