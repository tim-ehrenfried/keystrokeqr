import AppKit

/// „Über KeystrokeQR Host“ im dunklen KeystrokeQR-Stil (kein NSAboutPanel-Default).
/// Zeigt App-Name, Version/Build dynamisch aus dem Bundle, Copyright, Kontakt
/// (mailto), GitHub-Link und Lizenz. Alle Strings zweisprachig über `L()`.
final class AboutWindowController: NSWindowController, NSWindowDelegate {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("about.window.title")
        window.isReleasedWhenClosed = false
        window.appearance = HostUI.appearance
        window.backgroundColor = HostUI.windowBackground
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// `CFBundleShortVersionString` (Marketing) und `CFBundleVersion` (Build)
    /// direkt aus dem laufenden Bundle — kein hartkodierter Wert.
    private static func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "–"
        let build = (info?["CFBundleVersion"] as? String) ?? "–"
        return String(format: L("about.version"), short, build)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

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

        let githubButton = HostUI.makeLinkButton(
            title: L("about.link.github"), target: self, action: #selector(openGitHub))
        let contactButton = HostUI.makeLinkButton(
            title: L("about.link.contact"), target: self, action: #selector(openContact))

        let linkRow = NSStackView(views: [githubButton, contactButton])
        linkRow.orientation = .horizontal
        linkRow.spacing = 20

        let stack = NSStackView(views: [icon, name, version, copyright, license, linkRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: name)
        stack.setCustomSpacing(18, after: copyright)
        stack.setCustomSpacing(18, after: license)
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    func present() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openGitHub() { NSWorkspace.shared.open(HostLinks.repository) }
    @objc private func openContact() { NSWorkspace.shared.open(HostLinks.contactMailto) }
}
