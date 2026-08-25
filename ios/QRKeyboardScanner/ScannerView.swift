import SwiftUI
import AVFoundation
import UIKit

/// Quadratisches Scan-Fenster (Region of Interest): volle Bildschirmbreite,
/// horizontal zentriert, Zentrum bei ~43 % der Bildschirmhöhe (etwas oberhalb
/// der Mitte). Wird von ScannerView (AVCaptureMetadataOutput.rectOfInterest)
/// UND vom SwiftUI-Overlay (Abdunkelung + Eckklammern) identisch verwendet —
/// beide rechnen auf denselben Vollbild-Koordinaten (ignoresSafeArea).
enum ScanRegion {
    /// Vertikales Zentrum des Fensters als Anteil der Bildschirmhöhe.
    static let centerYFraction: CGFloat = 0.43
    /// Eckenradius des sichtbaren Ausschnitts.
    static let cornerRadius: CGFloat = 24

    /// 1:1-Ausschnitt in Vollbild-Koordinaten der übergebenen Größe.
    static func rect(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height)
        let centerY = size.height * centerYFraction
        let y = max(0, min(centerY - side / 2, size.height - side))
        return CGRect(x: (size.width - side) / 2, y: y, width: side, height: side)
    }
}

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

    /// Wird bei jeder (nicht im Cooldown befindlichen) Erkennung eines NEUEN
    /// Codes aufgerufen — auf dem MainActor.
    var onScan: (String) -> Void
    /// Entscheidet, ob ein erkannter Code automatisch gesendet wird.
    /// Liefert false (Code wurde bereits gesendet) → keine Auto-Übertragung,
    /// stattdessen `onRepeatDetection`.
    var shouldAutoSend: (String) -> Bool = { _ in true }
    /// Bereits gesendeter Code ist (weiterhin) im Bild — entprellt gemeldet
    /// (max. ~4x/s), damit die UI ihren Auslöser-Button anzeigen/verlängern kann.
    /// Im Push-to-Send-Modus (`shouldAutoSend` liefert immer false) meldet
    /// dieser Kanal JEDEN aktuell erkannten Code — er speist den Send-Button.
    var onRepeatDetection: (String) -> Void = { _ in }
    /// Steuert Start/Stop der Capture-Session (App aktiv/inaktiv).
    var isActive: Bool
    /// Gate für die Erfolgs-Haptik beim Auto-Senden (Setting „Haptik beim Senden“).
    var playScanHaptics: Bool = true
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
        view.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateRectOfInterest()
        }
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
        context.coordinator.shouldAutoSend = shouldAutoSend
        context.coordinator.onRepeatDetection = onRepeatDetection
        context.coordinator.onRunningChanged = onRunningChanged
        context.coordinator.playScanHaptics = playScanHaptics
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
        /// Nach jedem Layout-Durchlauf aufgerufen — der Coordinator rechnet dann
        /// das Scan-Fenster (`ScanRegion`) neu in `rectOfInterest` um.
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {

        var onScan: (String) -> Void
        var shouldAutoSend: (String) -> Bool = { _ in true }
        var onRepeatDetection: (String) -> Void = { _ in }
        var onRunningChanged: ((Bool) -> Void)?
        var playScanHaptics = true
        /// Zuletzt verarbeiteter Reset-Token (siehe `ScannerView.resetToken`).
        var resetToken = 0

        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "de.timehrenfried.keystrokeqr.capture")
        private var isConfigured = false
        private var isRunning = false
        private weak var previewView: PreviewView?
        private var videoDevice: AVCaptureDevice?
        private var metadataOutput: AVCaptureMetadataOutput?
        private var subjectAreaObserver: NSObjectProtocol?

        /// Bis zu diesem Zeitpunkt werden erkannte Codes ignoriert (1-s-Cooldown).
        private var cooldownUntil = Date.distantPast
        private let feedbackGenerator = UINotificationFeedbackGenerator()
        private let repeatFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

        // Entprellung für bereits gesendete Codes (AVCaptureMetadataOutput
        // feuert pro Frame): eine „Sichtung" läuft, solange derselbe Code ohne
        // Lücke > `repeatSightingGap` erkannt wird. Haptik nur einmal pro
        // Sichtung; UI-Benachrichtigungen auf max. ~4x/s gedrosselt.
        private var currentRepeatPayload: String?
        private var lastRepeatSeen = Date.distantPast
        private var lastRepeatNotified = Date.distantPast
        private let repeatSightingGap: TimeInterval = 2.5
        private let repeatNotifyInterval: TimeInterval = 0.25
        /// Zoom-Faktor zu Beginn einer Pinch-Geste.
        private var pinchStartZoom: CGFloat = 1.0

        // Outlines um alle aktuell sichtbaren Codes (wie der System-Scanner):
        // der GEWÄHLTE (mittigste) Code gelb, übrige dezent weiß.
        // CAShapeLayer direkt über dem Preview-Layer —
        // performant, kein SwiftUI-Redraw pro Frame. Ein Layer pro Code,
        // Pfad-Updates animieren implizit; verschwundene Codes faden nach
        // ~0,3 s aus.
        private var outlineLayers: [String: CAShapeLayer] = [:]
        private var outlineLastSeen: [String: Date] = [:]
        private var outlineCleanupTimer: Timer?
        private let outlineTimeout: TimeInterval = 0.3

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
            outlineCleanupTimer?.invalidate()
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
                    DispatchQueue.main.async { self.removeAllOutlines() }
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
                // Nach dem Session-Start ist die Preview-Layer-Zuordnung gültig —
                // jetzt (und bei jedem Layout) das Scan-Fenster als ROI setzen.
                if running {
                    self?.updateRectOfInterest()
                }
            }
        }

        /// Begrenzung der Erkennung auf das Scan-Fenster (`ScanRegion`):
        /// rechnet das Fenster von Layer- in normalisierte Capture-Koordinaten
        /// um (`metadataOutputRectConverted(fromLayerRect:)`) — das geht erst,
        /// wenn Session UND Layout stehen; bis dahin liefert die Umrechnung ein
        /// leeres Rechteck und wir versuchen es beim nächsten Auslöser erneut.
        /// Main-Thread (Layer/Bounds); das Setzen selbst auf der sessionQueue.
        func updateRectOfInterest() {
            guard let previewView, let output = metadataOutput,
                  previewView.bounds.width > 0 else { return }
            let layerRect = ScanRegion.rect(in: previewView.bounds.size)
            let converted = previewView.videoPreviewLayer
                .metadataOutputRectConverted(fromLayerRect: layerRect)
            guard converted.width > 0, converted.height > 0,
                  converted.width.isFinite, converted.height.isFinite else { return }
            sessionQueue.async {
                output.rectOfInterest = converted
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
            metadataOutput = output

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

        /// Ein im aktuellen Frame erkannter Code mit vorab berechneten
        /// Layer-Koordinaten: `transformed` (perspektivische Ecken für die
        /// Outline) und `distanceToWindowCenter` (Zentrum der transformierten
        /// Bounds ↔ Mitte des Scan-Fensters) für die Ziel-Auswahl.
        private struct DetectedCode {
            let payload: String?
            let key: String
            let transformed: AVMetadataMachineReadableCodeObject?
            let distanceToWindowCenter: CGFloat
        }

        /// Sammelt alle maschinenlesbaren Codes des Frames und rechnet sie
        /// einmalig in Layer-Koordinaten um (Basis für Auswahl UND Outlines).
        private func detectedCodes(from objects: [AVMetadataObject]) -> [DetectedCode] {
            guard let previewView else { return [] }
            let previewLayer = previewView.videoPreviewLayer
            let windowRect = ScanRegion.rect(in: previewView.bounds.size)
            let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)

            return objects.compactMap { object in
                guard let code = object as? AVMetadataMachineReadableCodeObject else { return nil }
                let transformed = previewLayer.transformedMetadataObject(for: code)
                    as? AVMetadataMachineReadableCodeObject
                let distance: CGFloat
                if let transformed {
                    distance = hypot(
                        transformed.bounds.midX - windowCenter.x,
                        transformed.bounds.midY - windowCenter.y
                    )
                } else {
                    // Ohne Layer-Zuordnung (sollte nicht vorkommen) nie bevorzugen.
                    distance = .greatestFiniteMagnitude
                }
                return DetectedCode(
                    payload: code.stringValue,
                    key: code.stringValue ?? "type:\(code.type.rawValue)",
                    transformed: transformed,
                    distanceToWindowCenter: distance
                )
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let now = Date()

            // Zielen bei MEHREREN Codes im Fenster: deterministisch gewinnt
            // der Code, dessen Zentrum am nächsten an der Mitte des
            // Scan-Fensters liegt — er speist Kandidat/Vorschau/Senden
            // (Push-Modus) UND Auto-Send (Continuous). Durch Bewegen des
            // iPhones „zielt“ man so auf den gewünschten Code.
            let codes = detectedCodes(from: metadataObjects)
            let selected = codes
                .filter { $0.payload?.isEmpty == false }
                .min { $0.distanceToWindowCenter < $1.distanceToWindowCenter }

            // Outlines immer aktualisieren — für ALLE sichtbaren Codes,
            // unabhängig von Cooldown und Sent-Status. Der GEWÄHLTE Code
            // bekommt die gelbe Outline, alle übrigen eine dezente weiße.
            updateOutlines(for: codes, selectedKey: selected?.key, at: now)

            guard now >= cooldownUntil else { return }
            guard let text = selected?.payload else { return }

            if shouldAutoSend(text) {
                // Neuer Code: exakt 1 Sekunde Cooldown, keine weitere Verarbeitung.
                cooldownUntil = now.addingTimeInterval(1.0)

                // Haptisches Feedback (Setting-gesteuert) + Sucher kurz einfrieren.
                if playScanHaptics {
                    feedbackGenerator.notificationOccurred(.success)
                }
                freezePreview(for: 1.0)

                onScan(text)
            } else {
                handleRepeatDetection(text, at: now)
            }
        }

        /// Bereits gesendeter Code im Bild: kein Auto-Send, dezente Haptik nur
        /// einmal pro Sichtung, gedrosselte UI-Benachrichtigung (kein Spam).
        private func handleRepeatDetection(_ text: String, at now: Date) {
            let isNewSighting = text != currentRepeatPayload
                || now.timeIntervalSince(lastRepeatSeen) > repeatSightingGap
            if isNewSighting {
                repeatFeedbackGenerator.impactOccurred()
            }
            currentRepeatPayload = text
            lastRepeatSeen = now

            if isNewSighting || now.timeIntervalSince(lastRepeatNotified) >= repeatNotifyInterval {
                lastRepeatNotified = now
                onRepeatDetection(text)
            }
        }

        // MARK: Code-Outlines (Main-Thread)

        private func updateOutlines(
            for codes: [DetectedCode],
            selectedKey: String?,
            at now: Date
        ) {
            guard let previewView else { return }
            let previewLayer = previewView.videoPreviewLayer

            for code in codes {
                guard let transformed = code.transformed,
                      transformed.corners.count >= 4 else { continue }

                // Stabiler Schlüssel pro Code: Payload, sonst Symbologie.
                let key = code.key
                let path = Self.roundedOutlinePath(corners: transformed.corners).cgPath
                let isSelected = key == selectedKey

                let shape: CAShapeLayer
                if let existing = outlineLayers[key] {
                    shape = existing
                    // Pfad-Änderungen animieren bei Standalone-Layern implizit
                    // (~0,25 s) → sanftes Nachführen der Position.
                    shape.path = path
                } else {
                    shape = CAShapeLayer()
                    shape.lineWidth = 3
                    shape.lineJoin = .round
                    shape.lineCap = .round
                    shape.shadowOffset = .zero
                    shape.path = path
                    previewLayer.addSublayer(shape)
                    outlineLayers[key] = shape
                }
                // Ziel-Feedback: der GEWÄHLTE (mittigste) Code leuchtet gelb,
                // alle anderen sichtbaren Codes bekommen eine dezente weiße,
                // gedimmte Outline — Wechsel animieren implizit weich.
                Self.applyOutlineStyle(to: shape, selected: isSelected)
                outlineLastSeen[key] = now
            }

            if !outlineLastSeen.isEmpty, outlineCleanupTimer == nil {
                outlineCleanupTimer = Timer.scheduledTimer(
                    withTimeInterval: 0.1,
                    repeats: true
                ) { [weak self] _ in
                    self?.cleanupOutlines()
                }
            }
        }

        /// Entfernt Outlines von Codes, die das Bild verlassen haben
        /// (kurzes Fade-out, dann Layer weg).
        private func cleanupOutlines() {
            let now = Date()
            for (key, lastSeen) in outlineLastSeen
            where now.timeIntervalSince(lastSeen) > outlineTimeout {
                if let shape = outlineLayers[key] {
                    Self.fadeOutAndRemove(shape)
                }
                outlineLayers.removeValue(forKey: key)
                outlineLastSeen.removeValue(forKey: key)
            }
            if outlineLastSeen.isEmpty {
                outlineCleanupTimer?.invalidate()
                outlineCleanupTimer = nil
            }
        }

        private func removeAllOutlines() {
            for shape in outlineLayers.values {
                shape.removeFromSuperlayer()
            }
            outlineLayers.removeAll()
            outlineLastSeen.removeAll()
            outlineCleanupTimer?.invalidate()
            outlineCleanupTimer = nil
        }

        /// Farbstil je Auswahlzustand: gelb + Glow für den gewählten Code,
        /// dezentes gedimmtes Weiß ohne Glow für alle übrigen.
        private static func applyOutlineStyle(to shape: CAShapeLayer, selected: Bool) {
            if selected {
                shape.strokeColor = UIColor.systemYellow.cgColor
                shape.fillColor = UIColor.systemYellow.withAlphaComponent(0.08).cgColor
                shape.shadowColor = UIColor.systemYellow.cgColor
                shape.shadowOpacity = 0.55
                shape.shadowRadius = 4
            } else {
                shape.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
                shape.fillColor = UIColor.white.withAlphaComponent(0.04).cgColor
                shape.shadowColor = UIColor.clear.cgColor
                shape.shadowOpacity = 0
                shape.shadowRadius = 0
            }
        }

        private static func fadeOutAndRemove(_ shape: CAShapeLayer) {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                shape.removeFromSuperlayer()
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.3
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            shape.add(fade, forKey: "fadeOut")
            CATransaction.commit()
        }

        /// Abgerundeter Pfad durch die (perspektivisch verzerrten) vier Ecken.
        private static func roundedOutlinePath(
            corners: [CGPoint],
            radius: CGFloat = 6
        ) -> UIBezierPath {
            let path = UIBezierPath()
            let count = corners.count
            guard count >= 3 else { return path }

            for index in 0..<count {
                let current = corners[index]
                let previous = corners[(index - 1 + count) % count]
                let next = corners[(index + 1) % count]

                let toPrevious = unitVector(from: current, to: previous)
                let toNext = unitVector(from: current, to: next)
                // Radius nie größer als die halbe kürzere Kante.
                let maxRadius = min(
                    radius,
                    distance(current, previous) / 2,
                    distance(current, next) / 2
                )
                let start = CGPoint(
                    x: current.x + toPrevious.dx * maxRadius,
                    y: current.y + toPrevious.dy * maxRadius
                )
                let end = CGPoint(
                    x: current.x + toNext.dx * maxRadius,
                    y: current.y + toNext.dy * maxRadius
                )
                if index == 0 {
                    path.move(to: start)
                } else {
                    path.addLine(to: start)
                }
                path.addQuadCurve(to: end, controlPoint: current)
            }
            path.close()
            return path
        }

        private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(b.x - a.x, b.y - a.y)
        }

        private static func unitVector(from: CGPoint, to: CGPoint) -> CGVector {
            let length = distance(from, to)
            guard length > 0 else { return CGVector(dx: 0, dy: 0) }
            return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
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
                .accessibilityHidden(true)
            Text("No camera access")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("The app needs access to the camera to scan codes. Please allow access in Settings.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens the iOS Settings app to grant camera access.")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
