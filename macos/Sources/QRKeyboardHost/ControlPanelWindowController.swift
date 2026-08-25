import AppKit

/// Zentrales „KeystrokeQR“-Panel (Kontrollzentrum) im dunklen KeystrokeQR-Stil.
/// Bündelt die früher über einzelne Menüpunkte verstreuten Funktionen:
/// Verbindungsstatus, Bedienungshilfen-Status (LIVE), gekoppelte Geräte
/// (inkl. Entfernen + Neu-Pairing), Tippgeschwindigkeit sowie Zugänge zu Hilfe
/// und Über. Alle nutzersichtbaren Strings zweisprachig über `L()`.
///
/// Läuft in der `.accessory`-App als normales, fokussierbares Fenster
/// (`present()` aktiviert die App + bringt das Fenster nach vorn).
final class ControlPanelWindowController: NSWindowController, NSWindowDelegate {

    /// Aktionen, die der Host (AppDelegate) für das Panel bereitstellt.
    struct Actions {
        let openAccessibility: () -> Void
        let pairDevice: () -> Void
        let removeDevice: (UUID) -> Void
        let showHelp: () -> Void
        let showAbout: () -> Void
        let showIntro: () -> Void
    }

    private let crypto: CryptoManager
    private let actions: Actions

    // Verbindungsstatus
    private let connectionLabel = NSTextField(labelWithString: "")
    private let portLabel = NSTextField(labelWithString: "")

    // Bedienungshilfen (live)
    private let axIcon = NSImageView()
    private let axStatusLabel = NSTextField(labelWithString: "")
    private let axDetailLabel = NSTextField(wrappingLabelWithString: "")

    // Gekoppelte Geräte
    private let devicesStack = NSStackView()

    // Tippgeschwindigkeit
    private let speedControl = NSSegmentedControl()

    private var lastState = ScanServer.State()
    private var accessibilityTimer: Timer?
    private var lastTrusted: Bool?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(crypto: CryptoManager, actions: Actions) {
        self.crypto = crypto
        self.actions = actions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("panel.window.title")
        window.isReleasedWhenClosed = false
        window.appearance = HostUI.appearance
        window.backgroundColor = HostUI.windowBackground
        window.minSize = NSSize(width: 420, height: 460)
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

        let sections = NSStackView(views: [
            header,
            makeConnectionCard(),
            makeAccessibilityCard(),
            makeDevicesCard(),
            makeTypingSpeedCard(),
            makeFooter()
        ])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 18
        sections.setCustomSpacing(20, after: header)
        sections.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        sections.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(sections)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView

        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            sections.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            sections.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            sections.topAnchor.constraint(equalTo: documentView.topAnchor),
            sections.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])
    }

    /// Karte mit Abschnittsüberschrift und beliebigem Inhalt, feste Breite (412),
    /// damit Fließtext umbricht und alle Karten bündig sind.
    private func makeCard(title: String, content inner: NSView) -> NSView {
        let card = HostUI.makeCard()
        let titleLabel = HostUI.makeSectionTitle(title)
        let stack = NSStackView(views: [titleLabel, inner])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(equalToConstant: 412)
        ])
        return card
    }

    private func makeConnectionCard() -> NSView {
        connectionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        connectionLabel.textColor = .labelColor
        portLabel.font = .systemFont(ofSize: 12)
        portLabel.textColor = .secondaryLabelColor

        let inner = NSStackView(views: [connectionLabel, portLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 4
        return makeCard(title: L("panel.section.connection"), content: inner)
    }

    private func makeAccessibilityCard() -> NSView {
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        axIcon.symbolConfiguration = config
        axIcon.setContentHuggingPriority(.required, for: .horizontal)

        axStatusLabel.font = .systemFont(ofSize: 15, weight: .bold)

        let statusRow = NSStackView(views: [axIcon, axStatusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        axDetailLabel.font = .systemFont(ofSize: 12)
        axDetailLabel.textColor = .secondaryLabelColor
        axDetailLabel.isEditable = false
        axDetailLabel.isSelectable = false
        axDetailLabel.drawsBackground = false
        axDetailLabel.preferredMaxLayoutWidth = 380

        let openButton = HostUI.makeSecondaryButton(
            title: L("menu.accessibility.open"), target: self, action: #selector(openAccessibility))
        openButton.setContentHuggingPriority(.required, for: .horizontal)

        let inner = NSStackView(views: [statusRow, axDetailLabel, openButton])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        NSLayoutConstraint.activate([
            axDetailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
        updateAccessibility(force: true)
        return makeCard(title: L("panel.section.accessibility"), content: inner)
    }

    private func makeDevicesCard() -> NSView {
        devicesStack.orientation = .vertical
        devicesStack.alignment = .leading
        devicesStack.spacing = 10

        let pairButton = HostUI.makePrimaryButton(
            title: L("menu.pairDevice"), target: self, action: #selector(pairDevice))
        // Kein Standard-Return-Key (das Panel ist kein modaler Dialog).
        pairButton.keyEquivalent = ""

        let inner = NSStackView(views: [devicesStack, pairButton])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 14
        rebuildDevices()
        return makeCard(title: L("panel.section.devices"), content: inner)
    }

    private func makeTypingSpeedCard() -> NSView {
        speedControl.segmentCount = TypingSpeed.allCases.count
        speedControl.segmentStyle = .rounded
        speedControl.trackingMode = .selectOne
        for (index, speed) in TypingSpeed.allCases.enumerated() {
            speedControl.setLabel(speed.localizedTitle, forSegment: index)
            speedControl.setWidth(96, forSegment: index)
        }
        speedControl.target = self
        speedControl.action = #selector(changeSpeed)
        syncSpeedSelection()

        let hint = HostUI.makeBodyLabel(L("menu.typingSpeed.tooltip"))
        hint.preferredMaxLayoutWidth = 380

        let inner = NSStackView(views: [speedControl, hint])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        NSLayoutConstraint.activate([
            hint.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
        return makeCard(title: L("panel.section.typingSpeed"), content: inner)
    }

    private func makeFooter() -> NSView {
        let helpButton = HostUI.makeSecondaryButton(
            title: L("panel.help.button"), target: self, action: #selector(showHelp))
        let aboutButton = HostUI.makeSecondaryButton(
            title: L("panel.about.button"), target: self, action: #selector(showAbout))
        let introButton = HostUI.makeLinkButton(
            title: L("panel.showIntro"), target: self, action: #selector(showIntro))

        let buttonRow = NSStackView(views: [helpButton, aboutButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let stack = NSStackView(views: [buttonRow, introButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    // MARK: - Öffentliche Aktualisierung

    /// Zeigt das Panel, aktiviert die App und startet den Live-Poll.
    func present() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refresh()
        startAccessibilityPolling()
    }

    /// Neuer Server-Zustand (Port, Dienstname, aktive Sitzungen). Kommt auf dem
    /// Main Thread an.
    func apply(state: ScanServer.State) {
        lastState = state
        updateConnection()
    }

    /// Baut Geräte-Liste neu auf und aktualisiert Verbindungs-/AX-Status.
    func refresh() {
        updateConnection()
        rebuildDevices()
        updateAccessibility(force: true)
    }

    // MARK: - Verbindungsstatus

    private func updateConnection() {
        let pairedCount = crypto.pairedDevices().count
        if pairedCount == 0 {
            connectionLabel.stringValue = L("menu.status.noDevice")
        } else {
            connectionLabel.stringValue = String(
                format: L("menu.status.pairedConnected"),
                pairedCount, lastState.activeSessionCount)
        }
        let portText = lastState.port.map(String.init) ?? "–"
        portLabel.stringValue = String(format: L("menu.port.format"), portText, lastState.serviceName)
    }

    // MARK: - Bedienungshilfen (live)

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateAccessibility(force: false)
        }
        // In .common, damit der Timer auch während Menü-/Fenster-Tracking feuert.
        RunLoop.main.add(timer, forMode: .common)
        accessibilityTimer = timer
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    /// Aktualisiert die Anzeige nur bei Änderung (oder `force`), um unnötige
    /// Layout-Arbeit während des Pollings zu vermeiden.
    private func updateAccessibility(force: Bool) {
        let trusted = KeyInjector.isTrusted()
        guard force || trusted != lastTrusted else { return }
        lastTrusted = trusted

        let symbol = trusted ? "checkmark.circle.fill" : "xmark.circle.fill"
        axIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        axIcon.contentTintColor = trusted ? .systemGreen : .systemRed
        axStatusLabel.stringValue = trusted ? L("panel.accessibility.enabled")
                                            : L("panel.accessibility.disabled")
        axStatusLabel.textColor = trusted ? .systemGreen : .systemRed
        axDetailLabel.stringValue = trusted ? L("panel.accessibility.enabled.detail")
                                            : L("panel.accessibility.disabled.detail")
    }

    // MARK: - Geräte-Liste

    private func rebuildDevices() {
        for view in devicesStack.arrangedSubviews {
            devicesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let devices = crypto.pairedDevices()
        guard !devices.isEmpty else {
            let empty = HostUI.makeBodyLabel(L("panel.devices.empty"))
            devicesStack.addArrangedSubview(empty)
            return
        }

        for device in devices {
            devicesStack.addArrangedSubview(makeDeviceRow(device))
        }
    }

    private func makeDeviceRow(_ device: CryptoManager.PairedDevice) -> NSView {
        let name = NSTextField(labelWithString: device.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = .labelColor

        let date = NSTextField(labelWithString: String(
            format: L("menu.device.pairedAt"), Self.dateFormatter.string(from: device.pairedAt)))
        date.font = .systemFont(ofSize: 11)
        date.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [name, date])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let removeButton = NSButton(
            title: L("menu.device.remove"), target: self, action: #selector(removeDevice(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .regular
        removeButton.contentTintColor = .systemRed
        removeButton.identifier = NSUserInterfaceItemIdentifier(device.deviceID.uuidString)
        removeButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textStack, spacer, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 380).isActive = true
        return row
    }

    // MARK: - Aktionen

    @objc private func openAccessibility() { actions.openAccessibility() }

    @objc private func pairDevice() { actions.pairDevice() }

    @objc private func removeDevice(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        actions.removeDevice(id)
        rebuildDevices()
        updateConnection()
    }

    @objc private func changeSpeed() {
        let index = speedControl.selectedSegment
        guard index >= 0, index < TypingSpeed.allCases.count else { return }
        TypingSpeed.current = TypingSpeed.allCases[index]
    }

    @objc private func showHelp() { actions.showHelp() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func showIntro() { actions.showIntro() }

    private func syncSpeedSelection() {
        if let index = TypingSpeed.allCases.firstIndex(of: TypingSpeed.current) {
            speedControl.selectedSegment = index
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Sofortige Auffrischung, sobald das Fenster den Fokus bekommt — der
        // Nutzer kommt evtl. gerade aus den Systemeinstellungen zurück.
        refresh()
        syncSpeedSelection()
        startAccessibilityPolling()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Poll pausieren, wenn das Fenster nicht aktiv ist (spart CPU); der
        // windowDidBecomeKey-Callback startet ihn wieder.
        stopAccessibilityPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopAccessibilityPolling()
    }
}
