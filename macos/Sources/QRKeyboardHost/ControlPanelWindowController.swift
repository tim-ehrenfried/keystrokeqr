import AppKit

/// Zentrales „KeystrokeQR“-Fenster im dunklen KeystrokeQR-Stil. Seit v0.10.0
/// **ein einziges Fenster** mit interner Navigation: Home (Kontrollzentrum),
/// „Hilfe“ und „Über“ werden als Unterseiten in denselben Fensterrahmen
/// geschoben. Oben links ein **Zurück-Button** (nur auf Unterseiten), oben
/// rechts — auf gleicher Höhe — ein dezenter grauer **„Einführung“-Button**.
///
/// Das Fenster öffnet für jede Seite genau so groß wie ihr Inhalt (kein Scroll):
/// beim Navigieren wird die Content-Größe berechnet und die Fenstergröße
/// animiert angepasst (`resizeWindow(to:)`), wobei die obere linke Ecke fix
/// bleibt.
///
/// Bündelt die früher über einzelne Menüpunkte/Fenster verstreuten Funktionen:
/// Verbindungsstatus, Bedienungshilfen-Status (LIVE), gekoppelte Geräte
/// (inkl. Entfernen + Neu-Pairing), Tippgeschwindigkeit sowie Hilfe und Über.
/// Alle nutzersichtbaren Strings zweisprachig über `L()`.
///
/// Läuft in der `.accessory`-App als normales, fokussierbares Fenster
/// (`present()` aktiviert die App + bringt das Fenster nach vorn).
final class ControlPanelWindowController: NSWindowController, NSWindowDelegate {

    /// Aktionen, die der Host (AppDelegate) für das Fenster bereitstellt.
    /// Hilfe/Über liegen jetzt als Unterseiten im Fenster selbst — nur die
    /// „Einführung“ (Onboarding) bleibt ein eigenes Fenster.
    struct Actions {
        let openAccessibility: () -> Void
        let pairDevice: () -> Void
        let removeDevice: (UUID) -> Void
        let showIntro: () -> Void
    }

    private enum Page {
        case home, help, about
    }

    private let crypto: CryptoManager
    private let actions: Actions

    // Navigation
    private static let topBarHeight: CGFloat = 44
    private static let homeWidth: CGFloat = 460
    private static let helpWidth: CGFloat = 460
    private static let aboutWidth: CGFloat = 440

    private let contentContainer = NSView()
    private var backButton: NSButton!
    private var introButton: NSButton!
    private var currentPage: Page = .home
    private var currentPageView: NSView?

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

    // Seiten werden einmalig gebaut und wiederverwendet (Home enthält
    // live-aktualisierte Labels, deren Referenzen erhalten bleiben müssen).
    private lazy var homeView: NSView = makeHomeView()
    private lazy var helpView: NSView = makeHelpView()
    private lazy var aboutView: NSView = makeAboutView()

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
            contentRect: NSRect(x: 0, y: 0, width: Self.homeWidth, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("panel.window.title")
        window.isReleasedWhenClosed = false
        window.appearance = HostUI.appearance
        window.backgroundColor = HostUI.windowBackground
        super.init(window: window)
        window.delegate = self
        buildChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Fenster-Gerüst (Top-Bar + Container)

    private func buildChrome() {
        guard let content = window?.contentView else { return }

        backButton = HostUI.makeToolbarButton(
            title: L("nav.back"), systemImage: "chevron.left",
            target: self, action: #selector(goBack))
        backButton.isHidden = true

        introButton = HostUI.makeToolbarButton(
            title: L("nav.intro"), systemImage: "sparkles",
            target: self, action: #selector(showIntro))

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        introButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backButton)
        topBar.addSubview(introButton)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(topBar)
        content.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: content.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Self.topBarHeight),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            introButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            introButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    // MARK: - Navigation

    private func view(for page: Page) -> NSView {
        switch page {
        case .home:  return homeView
        case .help:  return helpView
        case .about: return aboutView
        }
    }

    private func title(for page: Page) -> String {
        switch page {
        case .home:  return L("panel.window.title")
        case .help:  return L("help.window.title")
        case .about: return L("about.window.title")
        }
    }

    private func showPage(_ page: Page, animated: Bool) {
        let pageView = view(for: page)
        guard pageView !== currentPageView else { return }

        currentPageView?.removeFromSuperview()
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            pageView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pageView.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
        ])
        currentPageView = pageView
        currentPage = page

        backButton.isHidden = (page == .home)
        window?.title = title(for: page)

        if page == .home { refresh() }
        resizeWindow(to: pageView, animated: animated)
    }

    /// Passt die Fenstergröße exakt an die Seite an (kein Scroll). Hält die obere
    /// linke Ecke fix, animiert optional.
    private func resizeWindow(to pageView: NSView, animated: Bool) {
        guard let window else { return }
        contentContainer.layoutSubtreeIfNeeded()
        let fitting = pageView.fittingSize
        let contentSize = NSSize(width: fitting.width,
                                 height: Self.topBarHeight + fitting.height)
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var frame = window.frame
        frame.origin.y += frame.height - newFrame.height   // obere Kante fix
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: animated)
    }

    @objc private func goBack() { showPage(.home, animated: true) }
    @objc private func showIntro() { actions.showIntro() }
    @objc private func showHelp() { showPage(.help, animated: true) }
    @objc private func showAbout() { showPage(.about, animated: true) }

    // MARK: - Home-Seite

    private func makeHomeView() -> NSView {
        let header = HostUI.makeHeader()

        let sections = NSStackView(views: [
            header,
            makeConnectionCard(),
            makeAccessibilityCard(),
            makeDevicesCard(),
            makeTypingSpeedCard(),
            makeHomeFooter()
        ])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 18
        sections.setCustomSpacing(20, after: header)
        sections.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        sections.translatesAutoresizingMaskIntoConstraints = false
        sections.widthAnchor.constraint(equalToConstant: Self.homeWidth).isActive = true
        return sections
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
        // Kein Standard-Return-Key (das Fenster ist kein modaler Dialog).
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

    /// Fußzeile der Home-Ansicht: Einstiege in die Unterseiten Hilfe & Über.
    private func makeHomeFooter() -> NSView {
        let helpButton = HostUI.makeSecondaryButton(
            title: L("panel.help.button"), target: self, action: #selector(showHelp))
        let aboutButton = HostUI.makeSecondaryButton(
            title: L("panel.about.button"), target: self, action: #selector(showAbout))

        let buttonRow = NSStackView(views: [helpButton, aboutButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        return buttonRow
    }

    // MARK: - Hilfe-Seite

    private func makeHelpView() -> NSView {
        let header = HostUI.makeHeader()

        let title = NSTextField(labelWithString: L("help.title"))
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = .labelColor

        let quickCard = makeHelpTextCard(
            title: L("help.quickstart.title"),
            body: L("help.quickstart.body"))
        let troubleCard = makeHelpTroubleCard()

        let linksTitle = HostUI.makeSectionTitle(L("help.links.title"))
        let githubButton = HostUI.makeIconButton(
            title: L("help.link.github"), systemImage: "chevron.left.forwardslash.chevron.right",
            target: self, action: #selector(openRepo))
        let docsButton = HostUI.makeIconButton(
            title: L("help.link.docs"), systemImage: "book",
            target: self, action: #selector(openDocs))
        let linksStack = NSStackView(views: [linksTitle, githubButton, docsButton])
        linksStack.orientation = .vertical
        linksStack.alignment = .leading
        linksStack.spacing = 8

        let stack = NSStackView(views: [header, title, quickCard, troubleCard, linksStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(14, after: header)
        stack.setCustomSpacing(18, after: title)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.helpWidth).isActive = true
        return stack
    }

    private func makeHelpTextCard(title: String, body: String) -> NSView {
        let card = HostUI.makeCard()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        let bodyLabel = HostUI.makeBodyLabel(body)

        let inner = NSStackView(views: [titleLabel, bodyLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        embedCardContent(inner, in: card)
        return card
    }

    private func makeHelpTroubleCard() -> NSView {
        let card = HostUI.makeCard()

        let title = NSTextField(labelWithString: L("help.troubleshooting.title"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        func problem(_ head: String, _ text: String) -> NSStackView {
            let h = NSTextField(labelWithString: head)
            h.font = .systemFont(ofSize: 12, weight: .semibold)
            h.textColor = .labelColor
            let b = HostUI.makeBodyLabel(text)
            let s = NSStackView(views: [h, b])
            s.orientation = .vertical
            s.alignment = .leading
            s.spacing = 3
            return s
        }

        let notFound = problem(L("help.trouble.notFound.title"), L("help.trouble.notFound.body"))
        let notTyping = problem(L("help.trouble.notTyping.title"), L("help.trouble.notTyping.body"))

        let inner = NSStackView(views: [title, notFound, notTyping])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12
        embedCardContent(inner, in: card)
        return card
    }

    /// Verankert einen Inhalts-Stack mit Innenabstand in einer Karte (feste
    /// Kartenbreite, damit Fließtext sauber umbricht).
    private func embedCardContent(_ inner: NSStackView, in card: NSView) {
        inner.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(equalToConstant: 412)
        ])
    }

    // MARK: - Über-Seite

    private func makeAboutView() -> NSView {
        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        icon.image = NSImage(systemSymbolName: "qrcode.viewfinder",
                             accessibilityDescription: L("app.name"))?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .labelColor

        let name = NSTextField(labelWithString: L("app.name"))
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = .labelColor
        name.alignment = .center

        let version = NSTextField(labelWithString: Self.versionText())
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let copyright = NSTextField(labelWithString: L("about.copyright"))
        copyright.font = .systemFont(ofSize: 12)
        copyright.textColor = .secondaryLabelColor
        copyright.alignment = .center

        let license = NSTextField(labelWithString: L("about.license"))
        license.font = .systemFont(ofSize: 12)
        license.textColor = .secondaryLabelColor
        license.alignment = .center

        // Links als Buttons mit Icon (wie iOS-App) statt blauer Text-Links.
        let githubButton = HostUI.makeIconButton(
            title: L("about.link.github"), systemImage: "chevron.left.forwardslash.chevron.right",
            target: self, action: #selector(openGitHub))
        let contactButton = HostUI.makeIconButton(
            title: L("about.link.contact"), systemImage: "envelope",
            target: self, action: #selector(openContact))
        let docsButton = HostUI.makeIconButton(
            title: L("about.link.docs"), systemImage: "book",
            target: self, action: #selector(openDocs))

        let linkStack = NSStackView(views: [githubButton, contactButton, docsButton])
        linkStack.orientation = .vertical
        linkStack.alignment = .centerX
        linkStack.spacing = 10

        let stack = NSStackView(views: [icon, name, version, copyright, license, linkStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: name)
        stack.setCustomSpacing(18, after: copyright)
        stack.setCustomSpacing(22, after: license)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.aboutWidth).isActive = true
        return stack
    }

    /// `CFBundleShortVersionString` (Marketing) und `CFBundleVersion` (Build)
    /// direkt aus dem laufenden Bundle — kein hartkodierter Wert.
    private static func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "–"
        let build = (info?["CFBundleVersion"] as? String) ?? "–"
        return String(format: L("about.version"), short, build)
    }

    // MARK: - Öffentliche Aktualisierung

    /// Zeigt das Fenster (auf der Home-Ansicht), aktiviert die App und startet
    /// den Live-Poll.
    func present() {
        showPage(.home, animated: false)
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

    /// Aktualisiert Verbindungs-/AX-Status und die Geräte-Liste.
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

    @objc private func openRepo() { NSWorkspace.shared.open(HostLinks.repository) }
    @objc private func openDocs() { NSWorkspace.shared.open(HostLinks.docs) }
    @objc private func openGitHub() { NSWorkspace.shared.open(HostLinks.repository) }
    @objc private func openContact() { NSWorkspace.shared.open(HostLinks.contactMailto) }

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
