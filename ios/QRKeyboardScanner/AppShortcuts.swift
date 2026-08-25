import AppIntents
import Foundation

extension Notification.Name {
    /// Wird gepostet, wenn der Scanner in den Vordergrund soll
    /// (App Intent / Deep-Link) — ContentView reagiert darauf.
    static let startScanRequested = Notification.Name("de.timehrenfried.qr-keyboard-scanner.startScanRequested")
}

/// App Intent: bringt die App in den Vordergrund und aktiviert den Scanner.
/// Erscheint in der Shortcuts-App, in Spotlight, bei Siri und ist als
/// Aktion für den Action Button (iPhone 15 Pro+) wählbar.
struct StartScanIntent: AppIntent {
    static let title: LocalizedStringResource = "QR-Code scannen"
    static let description = IntentDescription("Öffnet den QR-Keyboard-Scanner und macht die Kamera scharf.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .startScanRequested, object: nil)
        return .result()
    }
}

/// Stellt die deutschen Siri-/Spotlight-Phrasen bereit.
struct QRKeyboardScannerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: [
                "Scanne QR-Code mit \(.applicationName)",
                "QR-Code scannen mit \(.applicationName)",
                "Starte den Scanner in \(.applicationName)",
                "Scanne einen Barcode mit \(.applicationName)"
            ],
            shortTitle: "QR-Code scannen",
            systemImageName: "qrcode.viewfinder"
        )
    }
}
