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
    private var server: ScanServer?
    private var typingSpeedItems: [NSMenuItem] = []

    private let connectionItem = NSMenuItem(title: L("menu.status.waiting"), action: nil, keyEquivalent: "")
    private let portItem = NSMenuItem(title: L("menu.port.placeholder"), action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: L("menu.accessibility.placeholder"), action: nil, keyEquivalent: "")
    private let pairedHeaderItem = NSMenuItem(title: L("menu.pairedDevices.header"), action: nil, keyEquivalent: "")
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
        pairedHeaderItem.isEnabled = false

        mainMenu.addItem(connectionItem)
        mainMenu.addItem(portItem)
        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(accessibilityItem)

        let openAXItem = NSMenuItem(
            title: L("menu.accessibility.open"),
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAXItem.target = self
        mainMenu.addItem(openAXItem)

        mainMenu.addItem(NSMenuItem.separator())

        let pairItem = NSMenuItem(
            title: L("menu.pairDevice"),
            action: #selector(openPairingWindow),
            keyEquivalent: ""
        )
        pairItem.target = self
        mainMenu.addItem(pairItem)

        mainMenu.addItem(pairedHeaderItem)
        // Geräte-Einträge werden in menuWillOpen(_:) dynamisch eingefügt
        // (nach pairedHeaderItem, vor dem folgenden Separator).

        mainMenu.addItem(NSMenuItem.separator())

        // Untermenü „Tippgeschwindigkeit“ (Schnell / Normal / Langsam).
        let speedItem = NSMenuItem(title: L("menu.typingSpeed"), action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        typingSpeedItems.removeAll()
        for speed in TypingSpeed.allCases {
            let item = NSMenuItem(
                title: speed.localizedTitle,
                action: #selector(selectTypingSpeed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = speed.rawValue
            item.toolTip = L("menu.typingSpeed.tooltip")
            speedMenu.addItem(item)
            typingSpeedItems.append(item)
        }
        speedItem.submenu = speedMenu
        mainMenu.addItem(speedItem)
        updateTypingSpeedChecks()

        let introItem = NSMenuItem(
            title: L("menu.showIntro"),
            action: #selector(showOnboardingFromMenu),
            keyEquivalent: ""
        )
        introItem.target = self
        mainMenu.addItem(introItem)

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
        rebuildPairedDevicesMenu()
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
    }

    private func updateAccessibilityItem() {
        if KeyInjector.isTrusted() {
            accessibilityItem.title = L("menu.accessibility.granted")
        } else {
            accessibilityItem.title = L("menu.accessibility.denied")
        }
    }

    /// Entfernt bisherige Geräte-Menüeinträge und fügt die aktuelle Liste
    /// gekoppelter Geräte (Name + Datum, je ein Untermenü mit „Entfernen“)
    /// direkt nach `pairedHeaderItem` wieder ein.
    private func rebuildPairedDevicesMenu() {
        guard let headerIndex = mainMenu.items.firstIndex(of: pairedHeaderItem) else { return }

        // Alle bisherigen dynamischen Geräte-Items (Tag 42) entfernen.
        var index = headerIndex + 1
        while index < mainMenu.items.count, mainMenu.items[index].tag == Self.deviceItemTag {
            mainMenu.removeItem(at: index)
        }

        let devices = crypto.pairedDevices()
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        for device in devices {
            let deviceItem = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            deviceItem.tag = Self.deviceItemTag
            let submenu = NSMenu()

            let dateItem = NSMenuItem(
                title: String(format: L("menu.device.pairedAt"), formatter.string(from: device.pairedAt)),
                action: nil, keyEquivalent: ""
            )
            dateItem.isEnabled = false
            submenu.addItem(dateItem)
            submenu.addItem(NSMenuItem.separator())

            let removeItem = NSMenuItem(
                title: L("menu.device.remove"),
                action: #selector(removeDevice(_:)),
                keyEquivalent: ""
            )
            removeItem.target = self
            removeItem.representedObject = device.deviceID
            submenu.addItem(removeItem)

            deviceItem.submenu = submenu
            mainMenu.insertItem(deviceItem, at: index)
            index += 1
        }
    }

    private static let deviceItemTag = 42

    // MARK: - Aktionen

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openPairingWindow() {
        let controller = pairingWindowController ?? PairingWindowController(coordinator: pairingCoordinator)
        pairingWindowController = controller
        controller.start()
    }

    @objc private func showOnboardingFromMenu() {
        showOnboarding()
    }

    private func showOnboarding() {
        let controller = onboardingWindowController ?? OnboardingWindowController(
            onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
            onPairDevice: { [weak self] in self?.openPairingWindow() }
        )
        onboardingWindowController = controller
        controller.present()
    }

    @objc private func selectTypingSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = TypingSpeed(rawValue: raw) else { return }
        TypingSpeed.current = speed
        updateTypingSpeedChecks()
    }

    private func updateTypingSpeedChecks() {
        let current = TypingSpeed.current
        for item in typingSpeedItems {
            let raw = item.representedObject as? String
            item.state = (raw == current.rawValue) ? .on : .off
        }
    }

    @objc private func removeDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? UUID else { return }
        crypto.removeDevice(deviceID)
        server?.disconnectDevice(deviceID)
        apply(state: lastState)
    }
}
