import AppKit

/// Fenster „Gerät koppeln…“ (Onboarding-Look): App-Kopf, großer 6-stelliger
/// Code in Einzelkästchen, Countdown-Fortschrittsbalken und freundliche
/// Statushinweise. Solange dieses Fenster offen ist, akzeptiert `ScanServer`
/// `pair_hello` (siehe `PairingCoordinator`).
///
/// Fehlerbehandlung ab v0.8.0 (docs/PROTOCOL-v2.md): Bei falschem Code erzeugt
/// der Coordinator sofort einen neuen OTP; dieses Fenster zeigt ihn an, setzt
/// den Countdown zurück und bleibt offen — kein roher Fehlercode im UI. Bei
/// Erfolg kurz „Gerät gekoppelt ✓“ und automatisches Schließen nach ~1,5 s.
final class PairingWindowController: NSWindowController, NSWindowDelegate {

    private static let otpLifetime: Double = 90

    private let coordinator: PairingCoordinator
    private var digitBoxes: [DigitBox] = []
    private let countdownLabel = NSTextField(labelWithString: "")
    private let progressBar = ProgressBarView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let newCodeButton: NSButton
    private var countdownTimer: Timer?
    private var isFinished = false

    init(coordinator: PairingCoordinator) {
        self.coordinator = coordinator
        self.newCodeButton = NSButton(title: L("pairing.newCode"), target: nil, action: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("pairing.window.title")
        window.isReleasedWhenClosed = false
        window.appearance = HostUI.appearance
        window.backgroundColor = HostUI.windowBackground
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - UI-Aufbau

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let header = HostUI.makeHeader()

        let subtitle = NSTextField(labelWithString: L("pairing.subtitle"))
        subtitle.font = .systemFont(ofSize: 20, weight: .bold)
        subtitle.textColor = .labelColor
        subtitle.alignment = .center

        let prompt = NSTextField(wrappingLabelWithString: L("pairing.prompt"))
        prompt.font = .systemFont(ofSize: 12)
        prompt.textColor = .secondaryLabelColor
        prompt.alignment = .center
        prompt.isEditable = false
        prompt.isSelectable = false
        prompt.drawsBackground = false

        // Sechs Ziffernkästchen, nach der dritten mit größerer Lücke gruppiert.
        var firstGroup: [NSView] = []
        var secondGroup: [NSView] = []
        for i in 0..<6 {
            let box = DigitBox()
            digitBoxes.append(box)
            if i < 3 { firstGroup.append(box) } else { secondGroup.append(box) }
        }
        let leftStack = NSStackView(views: firstGroup)
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        let rightStack = NSStackView(views: secondGroup)
        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        let codeStack = NSStackView(views: [leftStack, rightStack])
        codeStack.orientation = .horizontal
        codeStack.spacing = 22

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        progressBar.widthAnchor.constraint(equalToConstant: 300).isActive = true

        countdownLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        countdownLabel.alignment = .center

        newCodeButton.target = self
        newCodeButton.action = #selector(generateNewCode)
        newCodeButton.bezelStyle = .rounded
        newCodeButton.controlSize = .large
        newCodeButton.isHidden = true

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            header,
            subtitle,
            prompt,
            codeStack,
            progressBar,
            countdownLabel,
            newCodeButton,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(6, after: subtitle)
        stack.setCustomSpacing(22, after: prompt)
        stack.setCustomSpacing(18, after: codeStack)
        stack.setCustomSpacing(18, after: countdownLabel)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            prompt.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
    }

    // MARK: - Ablauf

    /// Startet ein frisches Pairing-Fenster (neues OTP) und zeigt es an.
    func start() {
        isFinished = false
        coordinator.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        let otp = coordinator.startSession()
        setOTP(otp)
        statusLabel.stringValue = L("pairing.waiting")
        statusLabel.textColor = .secondaryLabelColor
        restartCountdown()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setOTP(_ otp: String) {
        let digits = Array(otp)
        for (index, box) in digitBoxes.enumerated() {
            box.digit = index < digits.count ? String(digits[index]) : ""
        }
    }

    private func restartCountdown() {
        countdownTimer?.invalidate()
        tick()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let remaining = coordinator.remainingSeconds
        if remaining > 0 {
            countdownLabel.stringValue = String(format: L("pairing.countdown.valid"), remaining)
            progressBar.isHidden = false
            progressBar.progress = CGFloat(remaining) / Self.otpLifetime
            progressBar.fillColor = remaining <= 10 ? .systemRed
                : (remaining <= 30 ? .systemOrange : .systemGreen)
            newCodeButton.isHidden = true
        } else {
            countdownLabel.stringValue = L("pairing.countdown.expired")
            progressBar.isHidden = true
            newCodeButton.isHidden = false
            countdownTimer?.invalidate()
        }
    }

    @objc private func generateNewCode() {
        let otp = coordinator.regenerate()
        setOTP(otp)
        statusLabel.stringValue = L("pairing.waiting")
        statusLabel.textColor = .secondaryLabelColor
        restartCountdown()
    }

    private func handle(_ event: PairingCoordinator.PairingEvent) {
        switch event {
        case .paired:
            isFinished = true
            countdownTimer?.invalidate()
            progressBar.isHidden = true
            newCodeButton.isHidden = true
            countdownLabel.stringValue = ""
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = L("pairing.successShort")
            // Automatisch schließen (~1,5 s), damit der Nutzer den Erfolg sieht.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.close()
            }

        case .wrongCodeNewIssued(let newOTP):
            // Freundlicher Hinweis, neuer Code, Countdown zurück — Fenster offen.
            setOTP(newOTP)
            statusLabel.textColor = .systemOrange
            statusLabel.stringValue = L("pairing.badOTP")
            restartCountdown()

        case .expiredOrClosed:
            // Versuch traf ein abgelaufenes/geschlossenes Fenster.
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = L("pairing.countdown.expired")
            tick()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        countdownTimer?.invalidate()
        coordinator.onEvent = nil
        coordinator.endSession()
    }
}
