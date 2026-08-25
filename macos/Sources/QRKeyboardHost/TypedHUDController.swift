import AppKit

/// Modernes „✓ Getippt"-HUD nach erfolgreicher Keystroke-Injektion.
///
/// **Look (seit v0.12.0):** eine solide, dunkle, abgerundete Karte im
/// KeystrokeQR-Stil (kein „verwaschener" `NSVisualEffectView`/Blur mehr),
/// dezenter Rahmen + weicher Schatten, scharfer heller Text und ein Häkchen im
/// Marken-Gelb (#FFD60A). Weiche Ein-/Ausblendung.
///
/// **Position:** unten mittig, ca. 20 % der sichtbaren Bildschirmhöhe über der
/// Unterkante (`NSScreen.main.visibleFrame`) — nicht mehr oben.
///
/// **Kritisch (Fokus):** Das HUD darf NIEMALS den Tastaturfokus stehlen, sonst
/// bräche die Eingabe ins Zielfenster. Deshalb ein randloses, nicht-aktivierendes
/// Panel (`.nonactivatingPanel`), `isFloatingPanel = true`, `level = .statusBar`,
/// `ignoresMouseEvents = true`, `hidesOnDeactivate = false`. Es wird nur per
/// `orderFrontRegardless()` gezeigt — **nie** `makeKey`/`activate`. Bei schnellen
/// Folge-Scans wird dasselbe Panel wiederverwendet und der Auto-Ausblend-Timer
/// nur neu gestartet (kein Stapeln mehrerer Fenster).
///
/// Muss auf dem Main Thread benutzt werden (AppKit-UI).
@MainActor
final class TypedHUDController {

    static let shared = TypedHUDController()

    /// Sichtdauer, danach automatisch ausblenden.
    private static let visibleDuration: TimeInterval = 0.9
    private static let fadeInDuration: TimeInterval = 0.16
    private static let fadeOutDuration: TimeInterval = 0.22

    /// Anteil der sichtbaren Bildschirmhöhe, um den das HUD über der Unterkante
    /// schwebt (~20 %).
    private static let bottomFraction: CGFloat = 0.20

    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideTimer: Timer?

    private init() {}

    /// Zeigt kurz „✓ Getippt". Robust bei schnellen Folge-Aufrufen: bestehendes
    /// Panel wird wiederverwendet und nur der Timer neu gesetzt.
    func flash(_ text: String = L("hud.typed")) {
        let panel = panelForDisplay()
        label?.stringValue = text
        panel.setAccessibilityLabel(text)

        positionBottomCenter(panel)

        // Ohne Fokus-/Aktivierungswechsel einblenden.
        hideTimer?.invalidate()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
            }
        } else {
            // Bereits sichtbar (schneller Folge-Scan): nur voll deckend halten.
            panel.alphaValue = 1
        }

        let timer = Timer(timeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    // MARK: - Privat

    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func panelForDisplay() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = HostUI.appearance
        panel.setAccessibilityRole(.staticText)

        // Solide, kontrastreiche dunkle Karte (kein Blur) mit dezentem Rahmen.
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = HostUI.hudBackground.cgColor
        card.layer?.borderColor = HostUI.hudStroke.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        // Häkchen im Marken-Gelb.
        let check = NSImageView()
        let checkConfig = NSImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(checkConfig)
        check.contentTintColor = HostUI.brandYellow
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: L("hud.typed"))
        text.font = .systemFont(ofSize: 15, weight: .semibold)
        text.textColor = .labelColor
        text.alignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [check, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let content = NSView()
        content.addSubview(card)
        panel.contentView = content

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            card.topAnchor.constraint(equalTo: content.topAnchor),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13)
        ])

        self.panel = panel
        self.label = text
        return panel
    }

    /// Positioniert das HUD unten mittig, ca. 20 % der sichtbaren Bildschirmhöhe
    /// über der Unterkante.
    private func positionBottomCenter(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 180, height: 48))
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * Self.bottomFraction
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
