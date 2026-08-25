import AppKit

/// Gemeinsame Optik für Pairing- und Onboarding-Fenster (dezenter dunkler
/// Look). Bündelt Farben, Fonts und ein paar wiederverwendbare Bausteine, damit
/// beide Fenster konsistent aussehen. Reines AppKit, läuft in der `.accessory`-App.
enum HostUI {

    /// Beide Fenster erzwingen ein dunkles Erscheinungsbild, damit die
    /// semantischen Farben (labelColor etc.) auf dunklem Grund gerendert werden.
    static let appearance = NSAppearance(named: .darkAqua)

    // Farben
    static let windowBackground = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    static let cardFill         = NSColor(white: 1, alpha: 0.06)
    static let cardStroke       = NSColor(white: 1, alpha: 0.12)
    static let accent           = NSColor.controlAccentColor

    /// Marken-Gelb (#FFD60A) — passend zum iOS-Icon (Scan-Linie).
    static let brandYellow      = NSColor(calibratedRed: 1.0, green: 0.839, blue: 0.039, alpha: 1)

    /// Solider, kontrastreicher dunkler Grund für das „✓ Getippt“-HUD (kein Blur).
    static let hudBackground    = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.145, alpha: 1)
    static let hudStroke        = NSColor(white: 1, alpha: 0.14)

    /// App-Kopf: SF-Symbol + Wortmarke „KeystrokeQR Host“.
    static func makeHeader() -> NSView {
        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        icon.image = NSImage(systemSymbolName: "qrcode.viewfinder",
                             accessibilityDescription: L("app.name"))?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .labelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let wordmark = NSTextField(labelWithString: L("app.name"))
        wordmark.font = .systemFont(ofSize: 15, weight: .semibold)
        wordmark.textColor = .labelColor

        let row = NSStackView(views: [icon, wordmark])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// Karte mit abgerundeten Ecken und dezentem Rahmen.
    static func makeCard() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = cardFill.cgColor
        view.layer?.borderColor = cardStroke.cgColor
        view.layer?.borderWidth = 1
        view.layer?.cornerRadius = 14
        return view
    }

    /// Auffälliger Standardbutton (accent).
    static func makePrimaryButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        button.contentTintColor = accent
        return button
    }

    /// Zurückhaltender Sekundärbutton.
    static func makeSecondaryButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }

    /// Abschnittsüberschrift (klein, halbfett, gedämpft) für das Panel/Hilfe/Info.
    static func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    /// Fließtext-Label (umbrechend, gedämpft).
    static func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        return label
    }

    /// Button mit SF-Symbol + Label im dunklen Look (wie in der iOS-App): dezenter
    /// Rahmen, Symbol links, kein Akzentblau. Öffnet i. d. R. eine URL.
    static func makeIconButton(title: String, systemImage: String,
                               target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.contentTintColor = .labelColor
        button.keyEquivalent = ""
        return button
    }

    /// Dezenter, grauer Navigations-/Sekundärbutton (Zurück / Einführung) — gleiche
    /// Höhe/Baseline, kein Akzentblau. Optional mit führendem SF-Symbol.
    static func makeToolbarButton(title: String, systemImage: String? = nil,
                                  target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.contentTintColor = .secondaryLabelColor
        if let systemImage {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.keyEquivalent = ""
        return button
    }
}

/// Verbindliche externe Links (siehe docs/BRANDING.md, README).
enum HostLinks {
    static let repository = URL(string: "https://github.com/tim-ehrenfried/keystrokeqr")!
    static let docs = URL(string: "https://github.com/tim-ehrenfried/keystrokeqr/tree/main/docs")!
    static let contactMailto = URL(string: "mailto:mail@tim-ehrenfried.de")!
}

/// Schlanke, farbige Fortschrittsleiste (Countdown im Pairing-Fenster).
final class ProgressBarView: NSView {
    private let track = CALayer()
    private let fill = CALayer()

    /// 0…1.
    var progress: CGFloat = 1 { didSet { needsLayout = true } }
    var fillColor: NSColor = HostUI.accent {
        didSet { fill.backgroundColor = fillColor.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        track.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        track.cornerRadius = 3
        fill.backgroundColor = fillColor.cgColor
        fill.cornerRadius = 3
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        let width = max(0, min(1, progress)) * bounds.width
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        CATransaction.commit()
    }
}

/// Einzelnes Ziffernkästchen für den 6-stelligen Code.
final class DigitBox: NSView {
    private let label = NSTextField(labelWithString: "")

    var digit: String = "" {
        didSet { label.stringValue = digit }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = HostUI.cardFill.cgColor
        layer?.borderColor = HostUI.cardStroke.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 10

        label.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}
