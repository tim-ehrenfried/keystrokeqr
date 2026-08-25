import AppKit

/// Erst-Start-Einrichtungsassistent (einmalig, Persistenz via
/// `HostSettings.didCompleteOnboarding`). Führt durch den Ablauf
/// Willkommen → Funktionsweise → **Bedienungshilfen (live geprüft)** →
/// **„Gerät koppeln“** → **„Erfolgreich! Los geht’s“** → Kontrollpanel.
///
/// Die Bedienungshilfen-Berechtigung wird — analog zum Kontrollzentrum — **live**
/// geprüft: solange das Fenster aktiv ist, pollt ein Timer (~1,2 s)
/// `AXIsProcessTrusted()` und aktualisiert zusätzlich sofort in
/// `windowDidBecomeKey` (der Nutzer kommt evtl. gerade aus den Systemeinstellungen
/// zurück). Ist die Berechtigung erteilt, wird die Karte grün („Bedienungshilfen
/// aktiviert ✓“), der Button „Bedienungshilfen öffnen…“ ausgeblendet und
/// „Gerät koppeln“ aktiviert (ohne Berechtigung ist er deaktiviert, mit Hinweis).
///
/// Optik konsistent zum Pairing-Fenster (dunkler Look). Erneut aufrufbar über den
/// „Einführung“-Button im Kontrollzentrum. Alle Strings zweisprachig über `L()`.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let onOpenAccessibility: () -> Void
    /// Startet den bestehenden Pairing-Flow (PairingWindowController).
    private let onPairDevice: () -> Void
    /// Abschluss („Los geht’s“): Onboarding als erledigt markieren, schließen und
    /// zum Kontrollpanel springen.
    private let onFinish: () -> Void

    private static let contentWidth: CGFloat = 384

    // Bedienungshilfen-Karte (live aktualisiert).
    private let axIcon = NSImageView()
    private let axStatusLabel = NSTextField(labelWithString: "")
    private let axDetailLabel = NSTextField(wrappingLabelWithString: "")
    private var axOpenButton: NSButton!
    private var pairButton: NSButton!
    private let pairHint = NSTextField(wrappingLabelWithString: "")

    private var accessibilityTimer: Timer?
    private var lastTrusted: Bool?
    private var didPair = false

    // Seiten werden einmalig gebaut und wiederverwendet.
    private lazy var setupView: NSView = makeSetupView()
    private lazy var successView: NSView = makeSuccessView()
    private var currentView: NSView?

    init(onOpenAccessibility: @escaping () -> Void,
         onPairDevice: @escaping () -> Void,
         onFinish: @escaping () -> Void) {
        self.onOpenAccessibility = onOpenAccessibility
        self.onPairDevice = onPairDevice
        self.onFinish = onFinish
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Setup-Seite (Willkommen + Bedienungshilfen + Koppeln)

    private func makeSetupView() -> NSView {
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

        let card = makeAccessibilityCard()

        pairButton = HostUI.makePrimaryButton(
            title: L("menu.pairDevice"),
            target: self, action: #selector(pairDevice)
        )
        // Kein Standard-Return-Key (kein modaler Dialog).
        pairButton.keyEquivalent = ""

        pairHint.font = .systemFont(ofSize: 11)
        pairHint.textColor = .systemOrange
        pairHint.alignment = .center
        pairHint.isEditable = false
        pairHint.isSelectable = false
        pairHint.drawsBackground = false
        pairHint.stringValue = L("onboarding.pair.needsAccessibility")

        let stack = NSStackView(views: [header, title, body, card, pairButton, pairHint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(22, after: body)
        stack.setCustomSpacing(20, after: card)
        stack.setCustomSpacing(10, after: pairButton)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            card.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            pairHint.widthAnchor.constraint(lessThanOrEqualToConstant: Self.contentWidth)
        ])
        // WICHTIG: hier NICHT updateAccessibility() aufrufen — wir sind mitten im
        // lazy-Aufbau von `setupView`, und updateAccessibility referenziert
        // `setupView` (resize-Zweig) → re-entranter Zugriff auf den noch nicht
        // fertigen lazy-Initializer = Endlos-Rekursion/Absturz. Der Erststatus wird
        // in present() bzw. windowDidBecomeKey gesetzt (nach dem Aufbau).
        return stack
    }

    /// Bedienungshilfen-Karte mit Live-Status (Icon + Statuszeile + Erklärung +
    /// Button „Bedienungshilfen öffnen…“). Der Button verschwindet, sobald die
    /// Berechtigung erteilt ist.
    private func makeAccessibilityCard() -> NSView {
        let card = HostUI.makeCard()

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        axIcon.symbolConfiguration = iconConfig
        axIcon.setContentHuggingPriority(.required, for: .horizontal)
        axIcon.setAccessibilityElement(true)
        axIcon.setAccessibilityRole(.image)

        axStatusLabel.font = .systemFont(ofSize: 14, weight: .bold)

        let statusRow = NSStackView(views: [axIcon, axStatusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        axDetailLabel.font = .systemFont(ofSize: 12)
        axDetailLabel.textColor = .secondaryLabelColor
        axDetailLabel.isEditable = false
        axDetailLabel.isSelectable = false
        axDetailLabel.drawsBackground = false
        axDetailLabel.preferredMaxLayoutWidth = Self.contentWidth - 32

        axOpenButton = HostUI.makeSecondaryButton(
            title: L("menu.accessibility.open"),
            target: self, action: #selector(openAccessibility)
        )
        axOpenButton.setContentHuggingPriority(.required, for: .horizontal)

        let cardStack = NSStackView(views: [statusRow, axDetailLabel, axOpenButton])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 10
        cardStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            axDetailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.contentWidth - 32)
        ])
        return card
    }

    // MARK: - Erfolgs-Seite (nach dem Koppeln)

    private func makeSuccessView() -> NSView {
        let header = HostUI.makeHeader()

        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .semibold)
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                             accessibilityDescription: L("onboarding.success.title"))?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .systemGreen

        let title = NSTextField(labelWithString: L("onboarding.success.title"))
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .labelColor
        title.alignment = .center

        let body = NSTextField(wrappingLabelWithString: L("onboarding.success.body"))
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.isEditable = false
        body.isSelectable = false
        body.drawsBackground = false

        let startButton = HostUI.makePrimaryButton(
            title: L("onboarding.done"),
            target: self, action: #selector(finish)
        )
        startButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [header, icon, title, body, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(24, after: header)
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(24, after: body)
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 32, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
        return stack
    }

    // MARK: - Seiten-Wechsel

    private func show(_ pageView: NSView) {
        guard let content = window?.contentView, pageView !== currentView else { return }
        currentView?.removeFromSuperview()
        pageView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: content.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        currentView = pageView
        resizeWindow(to: pageView)
    }

    /// Passt die Fenstergröße an die Seite an (kein Scroll), obere Kante fix.
    private func resizeWindow(to pageView: NSView) {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let fitting = pageView.fittingSize
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: fitting))
        var frame = window.frame
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Ablauf

    func present() {
        // Immer frisch auf der Setup-Seite starten (Assistent kann erneut über
        // „Einführung“ geöffnet werden).
        didPair = false
        window?.title = L("onboarding.window.title")
        lastTrusted = nil
        show(setupView)
        updateAccessibility(force: true)
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        startAccessibilityPolling()
    }

    /// Wird vom Host aufgerufen, wenn das Pairing (aus dem Onboarding heraus)
    /// erfolgreich war. Zeigt den Erfolgs-Schritt „Erfolgreich gekoppelt! →
    /// Los geht’s“.
    func showPairingSuccess() {
        guard !didPair else { return }
        didPair = true
        stopAccessibilityPolling()
        window?.title = L("onboarding.success.title")
        show(successView)
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Bedienungshilfen (live)

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.updateAccessibility(force: false)
        }
        // .common, damit der Timer auch während Fenster-Tracking feuert.
        RunLoop.main.add(timer, forMode: .common)
        accessibilityTimer = timer
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    /// Aktualisiert die Karte nur bei Änderung (oder `force`). Erteilt →
    /// grüner Erfolgs-Zustand, „Öffnen…“-Button versteckt, „Gerät koppeln“ aktiv.
    private func updateAccessibility(force: Bool) {
        let trusted = KeyInjector.isTrusted()
        guard force || trusted != lastTrusted else { return }
        lastTrusted = trusted

        let symbol = trusted ? "checkmark.circle.fill" : "xmark.circle.fill"
        axIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        axIcon.contentTintColor = trusted ? .systemGreen : .systemRed

        axStatusLabel.stringValue = trusted ? L("onboarding.accessibility.granted")
                                            : L("panel.accessibility.disabled")
        axStatusLabel.textColor = trusted ? .systemGreen : .systemRed
        axIcon.setAccessibilityLabel(axStatusLabel.stringValue)

        axDetailLabel.stringValue = trusted ? L("panel.accessibility.enabled.detail")
                                            : L("onboarding.accessibility.body")

        // Button „Bedienungshilfen öffnen…“ nur nötig, solange nicht erteilt.
        axOpenButton?.isHidden = trusted

        // „Gerät koppeln“ erst freigeben, wenn getippt werden kann.
        pairButton?.isEnabled = trusted
        pairHint.isHidden = trusted

        // Höhe der Karte/Seite ändert sich (Button ein-/ausgeblendet) → nachziehen.
        if currentView === setupView {
            resizeWindow(to: setupView)
        }
    }

    // MARK: - Aktionen

    @objc private func openAccessibility() {
        onOpenAccessibility()
    }

    @objc private func pairDevice() {
        // Onboarding bleibt offen; der Host meldet Erfolg über
        // `showPairingSuccess()`.
        onPairDevice()
    }

    @objc private func finish() {
        onFinish()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Sofort auffrischen — der Nutzer kommt evtl. gerade aus den
        // Systemeinstellungen zurück, nachdem er die Berechtigung erteilt hat.
        updateAccessibility(force: true)
        if !didPair { startAccessibilityPolling() }
    }

    func windowDidResignKey(_ notification: Notification) {
        stopAccessibilityPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopAccessibilityPolling()
        // Einmal gezeigt reicht — beim nächsten Start nicht mehr automatisch.
        HostSettings.didCompleteOnboarding = true
    }
}
