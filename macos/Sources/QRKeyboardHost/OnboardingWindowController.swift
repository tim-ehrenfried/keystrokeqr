import AppKit

/// Erst-Start-Willkommensfenster (einmalig, Persistenz via
/// `HostSettings.didCompleteOnboarding`). Erklärt kurz, was die App tut
/// (iPhone scannt → Mac tippt), weist auf die nötige Bedienungshilfen-
/// Berechtigung hin und bietet „Bedienungshilfen öffnen…“ + „Gerät koppeln…“.
/// Optik konsistent zum Pairing-Fenster (dunkler Look). Erneut aufrufbar über
/// den Menüpunkt „Einführung anzeigen“.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let onOpenAccessibility: () -> Void
    private let onPairDevice: () -> Void

    init(onOpenAccessibility: @escaping () -> Void,
         onPairDevice: @escaping () -> Void) {
        self.onOpenAccessibility = onOpenAccessibility
        self.onPairDevice = onPairDevice
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("onboarding.window.title")
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

        let title = NSTextField(labelWithString: L("onboarding.title"))
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .labelColor
        title.alignment = .center

        let body = NSTextField(wrappingLabelWithString: L("onboarding.body"))
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.isEditable = false
        body.isSelectable = false
        body.drawsBackground = false

        // Bedienungshilfen-Karte mit Erklärung + Button.
        let card = HostUI.makeCard()
        let axTitle = NSTextField(labelWithString: L("onboarding.accessibility.title"))
        axTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        axTitle.textColor = .labelColor
        let axBody = NSTextField(wrappingLabelWithString: L("onboarding.accessibility.body"))
        axBody.font = .systemFont(ofSize: 12)
        axBody.textColor = .secondaryLabelColor
        axBody.isEditable = false
        axBody.isSelectable = false
        axBody.drawsBackground = false
        let axButton = HostUI.makeSecondaryButton(
            title: L("menu.accessibility.open"),
            target: self, action: #selector(openAccessibility)
        )
        axButton.setContentHuggingPriority(.required, for: .horizontal)

        let cardStack = NSStackView(views: [axTitle, axBody, axButton])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 8
        cardStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            axBody.widthAnchor.constraint(lessThanOrEqualToConstant: 350)
        ])

        let pairButton = HostUI.makePrimaryButton(
            title: L("menu.pairDevice"),
            target: self, action: #selector(pairDevice)
        )
        let doneButton = HostUI.makeSecondaryButton(
            title: L("onboarding.done"),
            target: self, action: #selector(dismissOnboarding)
        )

        let buttonRow = NSStackView(views: [doneButton, pairButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let stack = NSStackView(views: [header, title, body, card, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(22, after: body)
        stack.setCustomSpacing(24, after: card)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            card.widthAnchor.constraint(equalToConstant: 384)
        ])
    }

    // MARK: - Ablauf

    func present() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibility() {
        onOpenAccessibility()
    }

    @objc private func pairDevice() {
        // Onboarding als erledigt markieren und schließen, dann koppeln.
        HostSettings.didCompleteOnboarding = true
        onPairDevice()
        close()
    }

    @objc private func dismissOnboarding() {
        close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Einmal gezeigt reicht — beim nächsten Start nicht mehr automatisch.
        HostSettings.didCompleteOnboarding = true
    }
}
