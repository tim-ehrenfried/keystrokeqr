import AppKit

/// Nicht-aktivierendes Bestätigungs-Panel für den Modus „Bestätigen vor dem
/// Tippen" (`HostSettings.confirmBeforeTyping`). Zeigt eine gekürzte Vorschau
/// des gescannten Texts und „Tippen"/„Verwerfen".
///
/// **Fokus-Grundsatz:** Wie das HUD ist dies ein `.nonactivatingPanel`, das per
/// `orderFrontRegardless()` gezeigt wird — es aktiviert die App NICHT und lässt
/// damit die Fremd-App im Vordergrund/fokussiert. Das eigentliche
/// Re-Aktivieren der Ziel-App und das anschließende Tippen übernimmt der Aufrufer
/// (AppDelegate), nachdem der Nutzer „Tippen" gewählt hat.
///
/// Mehrere schnell hintereinander eintreffende Scans werden **serialisiert**:
/// Panels stapeln sich nicht, jede Anfrage wird nacheinander abgefragt, jede
/// bekommt genau eine Entscheidung.
@MainActor
final class ConfirmTypingPanelController {

    static let shared = ConfirmTypingPanelController()

    /// Maximale Zeichenzahl der Vorschau, danach mit „…" gekürzt.
    private static let previewLimit = 240

    struct Request {
        let text: String
        let autoTab: Bool
        let autoEnter: Bool
        /// `true` = tippen, `false` = verwerfen. Wird genau einmal aufgerufen.
        let decision: (Bool) -> Void
    }

    private var panel: NSPanel?
    private var previewLabel: NSTextField?
    private var metaLabel: NSTextField?
    private var queue: [Request] = []
    private var current: Request?

    private init() {}

    /// Reiht eine Bestätigungsanfrage ein und zeigt sie (ggf. nach der laufenden).
    func present(_ request: Request) {
        queue.append(request)
        if current == nil { showNext() }
    }

    // MARK: - Ablauf

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        current = request

        let panel = panelForDisplay()
        previewLabel?.stringValue = Self.previewText(for: request.text)
        metaLabel?.stringValue = Self.metaText(for: request)

        positionCenterTop(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func finish(type: Bool) {
        guard let request = current else { return }
        current = nil
        request.decision(type)
        if queue.isEmpty {
            panel?.orderOut(nil)
        } else {
            showNext()
        }
    }

    @objc private func typeTapped() { finish(type: true) }
    @objc private func discardTapped() { finish(type: false) }

    // MARK: - Aufbau

    private func panelForDisplay() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = HostUI.appearance

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L("confirm.title"))
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = .labelColor

        let preview = NSTextField(wrappingLabelWithString: "")
        preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        preview.textColor = .labelColor
        preview.maximumNumberOfLines = 6
        preview.lineBreakMode = .byTruncatingTail
        preview.setContentHuggingPriority(.defaultLow, for: .horizontal)
        preview.setAccessibilityLabel(L("confirm.preview.a11y"))

        let previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        previewBox.layer?.cornerRadius = 8
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 10),
            preview.trailingAnchor.constraint(equalTo: previewBox.trailingAnchor, constant: -10),
            preview.topAnchor.constraint(equalTo: previewBox.topAnchor, constant: 8),
            preview.bottomAnchor.constraint(equalTo: previewBox.bottomAnchor, constant: -8)
        ])

        let meta = NSTextField(labelWithString: "")
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor

        let discardButton = HostUI.makeSecondaryButton(
            title: L("confirm.discard"), target: self, action: #selector(discardTapped))
        discardButton.setAccessibilityLabel(L("confirm.discard"))
        let typeButton = HostUI.makePrimaryButton(
            title: L("confirm.type"), target: self, action: #selector(typeTapped))
        // Kein Return-Key: das Panel ist nicht-aktivierend, Bedienung per Klick.
        typeButton.keyEquivalent = ""
        typeButton.setAccessibilityLabel(L("confirm.type"))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, discardButton, typeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [title, previewBox, meta, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let content = NSView()
        content.addSubview(card)
        panel.contentView = content

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            card.topAnchor.constraint(equalTo: content.topAnchor),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
            previewBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36)
        ])

        self.panel = panel
        self.previewLabel = preview
        self.metaLabel = meta
        return panel
    }

    private func positionCenterTop(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 380, height: 200))
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 60
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Textaufbereitung

    static func previewText(for text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: "↩ ")
        if collapsed.count <= previewLimit { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: previewLimit)
        return String(collapsed[..<end]) + "…"
    }

    static func metaText(for request: Request) -> String {
        let count = request.text.count
        var parts = [String(format: L("confirm.charCount"), count)]
        if request.autoTab { parts.append(L("confirm.thenTab")) }
        if request.autoEnter { parts.append(L("confirm.thenEnter")) }
        return parts.joined(separator: " · ")
    }
}
