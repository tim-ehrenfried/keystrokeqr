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
    private var server: ScanServer?

    private let connectionItem = NSMenuItem(title: "Warte auf Verbindung", action: nil, keyEquivalent: "")
    private let portItem = NSMenuItem(title: "Port: – · Dienst: –", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Bedienungshilfen: –", action: nil, keyEquivalent: "")
    private let pairedHeaderItem = NSMenuItem(title: "Gekoppelte Geräte", action: nil, keyEquivalent: "")
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
                accessibilityDescription: "QR Keyboard Host"
            )
            image?.isTemplate = true // korrekt in Light & Dark Mode
            button.image = image
            button.toolTip = "QR Keyboard Host"
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
            title: "Bedienungshilfen öffnen…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAXItem.target = self
        mainMenu.addItem(openAXItem)

        mainMenu.addItem(NSMenuItem.separator())

        let pairItem = NSMenuItem(
            title: "Gerät koppeln…",
            action: #selector(openPairingWindow),
            keyEquivalent: ""
        )
        pairItem.target = self
        mainMenu.addItem(pairItem)

        mainMenu.addItem(pairedHeaderItem)
        // Geräte-Einträge werden in menuWillOpen(_:) dynamisch eingefügt
        // (nach pairedHeaderItem, vor dem folgenden Separator).

        mainMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Beenden",
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
            connectionItem.title = "Kein Gerät gekoppelt"
        } else {
            connectionItem.title = "\(pairedCount) gekoppelt · \(state.activeSessionCount) verbunden"
        }

        let portText = state.port.map(String.init) ?? "–"
        portItem.title = "Port: \(portText) · Dienst: \(state.serviceName)"
    }

    private func updateAccessibilityItem() {
        if KeyInjector.isTrusted() {
            accessibilityItem.title = "Bedienungshilfen: ✓ erteilt"
        } else {
            accessibilityItem.title = "Bedienungshilfen: ✗ nicht erteilt"
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
                title: "Gekoppelt: \(formatter.string(from: device.pairedAt))",
                action: nil, keyEquivalent: ""
            )
            dateItem.isEnabled = false
            submenu.addItem(dateItem)
            submenu.addItem(NSMenuItem.separator())

            let removeItem = NSMenuItem(
                title: "Entfernen",
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

    @objc private func removeDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? UUID else { return }
        crypto.removeDevice(deviceID)
        server?.disconnectDevice(deviceID)
        apply(state: lastState)
    }
}
