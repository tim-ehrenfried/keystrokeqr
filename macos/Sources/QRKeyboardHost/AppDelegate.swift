import AppKit

/// Menüleisten-App: NSStatusItem mit Verbindungs-, Port- und
/// Accessibility-Status sowie Pairing/Geräteverwaltung (docs/PROTOCOL-v2.md).
/// Alle UI-Updates laufen auf dem Main Thread.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let injector = KeyInjector()
    private let crypto = CryptoManager.shared
    private let pairingCoordinator = PairingCoordinator()
    private var pairingWindowController: PairingWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var controlPanelWindowController: ControlPanelWindowController?
    private var server: ScanServer?

    private let connectionItem = NSMenuItem(title: L("menu.status.waiting"), action: nil, keyEquivalent: "")
    private let portItem = NSMenuItem(title: L("menu.port.placeholder"), action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: L("menu.accessibility.placeholder"), action: nil, keyEquivalent: "")
    private let mainMenu = NSMenu()

    private var lastState = ScanServer.State()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        let server = ScanServer(injector: injector, crypto: crypto, pairingCoordinator: pairingCoordinator)
        server.onStateChange = { [weak self] state in
            // Callback kommt bereits auf dem Main Thread an.
            self?.apply(state: state)
        }
        self.server = server
        server.start()

        updateAccessibilityItem()

        // Beim allerersten Start einmalig das Willkommensfenster zeigen.
        if !HostSettings.didCompleteOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - Status-Item & Menü

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "qrcode.viewfinder",
                accessibilityDescription: L("app.name")
            )
            image?.isTemplate = true // korrekt in Light & Dark Mode
            button.image = image
            button.toolTip = L("app.name")
        }

        mainMenu.delegate = self

        connectionItem.isEnabled = false
        portItem.isEnabled = false
        accessibilityItem.isEnabled = false

        // Schlankes Menü: Status auf einen Blick (Verbindung, Port/Dienst,
        // Bedienungshilfen ✓/✗) + „KeystrokeQR öffnen…“ (Kontrollzentrum) +
        // „Beenden“. Alle weiteren Funktionen liegen im Panel.
        mainMenu.addItem(connectionItem)
        mainMenu.addItem(portItem)
        mainMenu.addItem(accessibilityItem)
        mainMenu.addItem(NSMenuItem.separator())

        let openPanelItem = NSMenuItem(
            title: L("menu.openPanel"),
            action: #selector(openControlPanel),
            keyEquivalent: ""
        )
        openPanelItem.target = self
        mainMenu.addItem(openPanelItem)

        mainMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: L("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        mainMenu.addItem(quitItem)

        item.menu = mainMenu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Accessibility-Status bei jedem Öffnen aktualisieren
        // (der Nutzer kann die Berechtigung jederzeit ändern).
        updateAccessibilityItem()
    }

    private func apply(state: ScanServer.State) {
        lastState = state
        let pairedCount = crypto.pairedDevices().count
        if pairedCount == 0 {
            connectionItem.title = L("menu.status.noDevice")
        } else {
            connectionItem.title = String(
                format: L("menu.status.pairedConnected"),
                pairedCount, state.activeSessionCount
            )
        }

        let portText = state.port.map(String.init) ?? "–"
        portItem.title = String(format: L("menu.port.format"), portText, state.serviceName)

        // Falls das Kontrollzentrum offen ist, denselben Zustand dorthin spiegeln.
        controlPanelWindowController?.apply(state: state)
    }

    private func updateAccessibilityItem() {
        if KeyInjector.isTrusted() {
            accessibilityItem.title = L("menu.accessibility.granted")
        } else {
            accessibilityItem.title = L("menu.accessibility.denied")
        }
    }

    // MARK: - Aktionen

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openControlPanel() {
        let controller = controlPanelWindowController ?? ControlPanelWindowController(
            crypto: crypto,
            actions: ControlPanelWindowController.Actions(
                openAccessibility: { [weak self] in self?.openAccessibilitySettings() },
                pairDevice: { [weak self] in self?.openPairingWindow() },
                removeDevice: { [weak self] id in self?.removeDevice(id) },
                showIntro: { [weak self] in self?.showOnboarding() }
            )
        )
        controlPanelWindowController = controller
        controller.present()
        controller.apply(state: lastState)
    }

    @objc private func openPairingWindow() {
        let controller = pairingWindowController ?? PairingWindowController(coordinator: pairingCoordinator)
        pairingWindowController = controller
        controller.start()
    }

    private func showOnboarding() {
        let controller = onboardingWindowController ?? OnboardingWindowController(
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            onPairDevice: { [weak self] in self?.openPairingWindow() }
        )
        onboardingWindowController = controller
        controller.present()
    }

    /// Entfernt ein Gerät: PSK aus der Keychain löschen UND die evtl. gerade
    /// aktive Sitzung dieses Geräts serverseitig trennen (docs/PROTOCOL-v2.md,
    /// „Geräteverwaltung“), damit der Client den Abbruch sofort bemerkt und in
    /// Neu-Pairing gehen kann. Ein späteres `session_hello` dieses `deviceID`
    /// beantwortet der Host mit `not_paired`.
    private func removeDevice(_ deviceID: UUID) {
        crypto.removeDevice(deviceID)
        server?.disconnectDevice(deviceID)
        apply(state: lastState)
    }
}
