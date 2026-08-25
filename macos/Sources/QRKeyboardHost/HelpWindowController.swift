import AppKit

/// In-App-Hilfe im dunklen KeystrokeQR-Stil: Kurzanleitung, Fehlerbehebung und
/// Links (GitHub-Repo, Dokumentation). Alle Strings zweisprachig über `L()`.
/// Der Inhalt scrollt, damit er auf kleinen Bildschirmen vollständig lesbar ist.
final class HelpWindowController: NSWindowController, NSWindowDelegate {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("help.window.title")
        window.isReleasedWhenClosed = false
        window.appearance = HostUI.appearance
        window.backgroundColor = HostUI.windowBackground
        window.minSize = NSSize(width: 420, height: 400)
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let header = HostUI.makeHeader()

        let title = NSTextField(labelWithString: L("help.title"))
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = .labelColor

        let quickCard = makeTextCard(
            title: L("help.quickstart.title"),
            body: L("help.quickstart.body")
        )

        let troubleCard = makeTroubleCard()

        let linksTitle = HostUI.makeSectionTitle(L("help.links.title"))
        let githubButton = HostUI.makeLinkButton(
            title: L("help.link.github"), target: self, action: #selector(openRepo))
        let docsButton = HostUI.makeLinkButton(
            title: L("help.link.docs"), target: self, action: #selector(openDocs))
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
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Scrollbarer Inhalt.
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

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

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])
    }

    /// Karte mit Titel + Fließtext.
    private func makeTextCard(title: String, body: String) -> NSView {
        let card = HostUI.makeCard()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        let bodyLabel = HostUI.makeBodyLabel(body)

        let inner = NSStackView(views: [titleLabel, bodyLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 8
        embed(inner, in: card)
        return card
    }

    /// Fehlerbehebungs-Karte mit zwei Fällen.
    private func makeTroubleCard() -> NSView {
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
        embed(inner, in: card)
        return card
    }

    /// Verankert einen Inhalts-Stack mit Innenabstand in einer Karte und begrenzt
    /// die Kartenbreite, damit der Fließtext sauber umbricht.
    private func embed(_ inner: NSStackView, in card: NSView) {
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

    func present() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openRepo() { NSWorkspace.shared.open(HostLinks.repository) }
    @objc private func openDocs() { NSWorkspace.shared.open(HostLinks.docs) }
}
