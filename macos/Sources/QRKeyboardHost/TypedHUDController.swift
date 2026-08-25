import AppKit

/// Dezentes „✓ Getippt"-HUD nach erfolgreicher Keystroke-Injektion.
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
    private static let visibleDuration: TimeInterval = 0.8
    private static let fadeDuration: TimeInterval = 0.18

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

        positionTopCenter(panel)

        // Ohne Fokus-/Aktivierungswechsel einblenden.
        hideTimer?.invalidate()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeDuration
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
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func panelForDisplay() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
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

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: L("hud.typed"))
        text.font = .systemFont(ofSize: 14, weight: .semibold)
        text.textColor = .labelColor
        text.alignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(text)

        let content = NSView()
        content.addSubview(container)
        panel.contentView = content

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.topAnchor.constraint(equalTo: content.topAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11)
        ])

        self.panel = panel
        self.label = text
        return panel
    }

    /// Positioniert das HUD dezent oben mittig, knapp unter der Menüleiste.
    private func positionTopCenter(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 160, height: 44))
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
