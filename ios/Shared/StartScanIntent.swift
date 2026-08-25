import AppIntents
import Foundation

extension Notification.Name {
    /// Wird gepostet, wenn der Scanner in den Vordergrund soll
    /// (App Intent / Deep-Link) — ContentView reagiert darauf.
    static let startScanRequested = Notification.Name("de.timehrenfried.qr-keyboard-scanner.startScanRequested")
}

/// App Intent: bringt die App in den Vordergrund und aktiviert den Scanner.
/// Erscheint in der Shortcuts-App, in Spotlight, bei Siri, ist als Aktion für
/// den Action Button (iPhone 15 Pro+) wählbar und treibt das iOS-18-Control-
/// Widget (Sperrbildschirm-Schnelltaste/Kontrollzentrum) an.
///
/// WICHTIG: Diese Datei ist bewusst Mitglied BEIDER Targets (App +
/// QRKeyboardScannerWidgets). Ein Control-Widget-Intent mit `openAppWhenRun`
/// wird vom System im App-Prozess ausgeführt — ist der Intent-Typ nur in der
/// Extension bekannt, tut der Button auf dem Sperrbildschirm sichtbar nichts.
struct StartScanIntent: AppIntent {
    static let title: LocalizedStringResource = "QR-Code scannen"
    static let description = IntentDescription("Öffnet den QR-Keyboard-Scanner und macht die Kamera scharf.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .startScanRequested, object: nil)
        return .result()
    }
}
