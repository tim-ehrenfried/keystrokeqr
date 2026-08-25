import AppKit

/// Menüleisten-App: NSStatusItem mit Verbindungs-, Port- und
/// Accessibility-Status. Alle UI-Updates laufen auf dem Main Thread.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let injector = KeyInjector()
    private var server: ScanServer?

    private let connectionItem = NSMenuItem(title: "Warte auf Verbindung", action: nil, keyEquivalent: "")
    private let portItem = NSMenuItem(title: "Port: – · Dienst: –", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Bedienungshilfen: –", action: nil, keyEquivalent: "")

    private var lastState = ScanServer.State()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        let server = ScanServer(injector: injector)
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

        let menu = NSMenu()
        menu.delegate = self

        connectionItem.isEnabled = false
        portItem.isEnabled = false
        accessibilityItem.isEnabled = false

        menu.addItem(connectionItem)
        menu.addItem(portItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(accessibilityItem)

        let openAXItem = NSMenuItem(
            title: "Bedienungshilfen öffnen…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAXItem.target = self
        menu.addItem(openAXItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Accessibility-Status bei jedem Öffnen aktualisieren
        // (der Nutzer kann die Berechtigung jederzeit ändern).
        updateAccessibilityItem()
    }

    private func apply(state: ScanServer.State) {
        lastState = state
        if state.connectionCount == 0 {
            connectionItem.title = "Warte auf Verbindung"
        } else if state.connectionCount == 1 {
            connectionItem.title = "1 Gerät verbunden"
        } else {
            connectionItem.title = "\(state.connectionCount) Geräte verbunden"
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

    // MARK: - Aktionen

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
