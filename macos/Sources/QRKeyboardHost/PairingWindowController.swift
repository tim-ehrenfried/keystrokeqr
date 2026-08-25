import AppKit

/// Fenster „Gerät koppeln…“: zeigt den 6-stelligen OTP + 90-s-Countdown.
/// Solange dieses Fenster offen ist, akzeptiert `ScanServer` `pair_hello`
/// (siehe `PairingCoordinator`). Schließen des Fensters beendet die Session
/// sofort — danach schlägt ein laufender Pairing-Versuch mit `pairing_closed`
/// fehl.
final class PairingWindowController: NSWindowController, NSWindowDelegate {

    private let coordinator: PairingCoordinator
    private let otpLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var countdownTimer: Timer?

    init(coordinator: PairingCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("pairing.window.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: L("pairing.prompt"))
        title.font = .systemFont(ofSize: 12)
        title.alignment = .center
        title.textColor = .secondaryLabelColor

        otpLabel.font = .monospacedDigitSystemFont(ofSize: 38, weight: .bold)
        otpLabel.alignment = .center

        countdownLabel.font = .systemFont(ofSize: 12)
        countdownLabel.textColor = .secondaryLabelColor
        countdownLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [title, otpLabel, countdownLabel, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 20, bottom: 22, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    /// Startet ein frisches Pairing-Fenster (neues OTP) und zeigt es an.
    func start() {
        coordinator.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        let otp = coordinator.startSession()
        otpLabel.stringValue = Self.formatted(otp)
        statusLabel.stringValue = L("pairing.waiting")
        statusLabel.textColor = .labelColor
        tick()
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func tick() {
        let remaining = coordinator.remainingSeconds
        countdownLabel.stringValue = remaining > 0
            ? String(format: L("pairing.countdown.valid"), remaining)
            : L("pairing.countdown.expired")
        if remaining <= 0 {
            countdownTimer?.invalidate()
        }
    }

    private func handle(_ event: PairingCoordinator.PairingEvent) {
        switch event {
        case .paired(let name):
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = String(format: L("pairing.success"), name)
            countdownTimer?.invalidate()
        case .failed(let reason):
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = String(format: L("pairing.failed"), reason)
        }
    }

    private static func formatted(_ otp: String) -> String {
        guard otp.count == 6 else { return otp }
        let mid = otp.index(otp.startIndex, offsetBy: 3)
        return "\(otp[otp.startIndex..<mid]) \(otp[mid...])"
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        countdownTimer?.invalidate()
        coordinator.onEvent = nil
        coordinator.endSession()
    }
}
