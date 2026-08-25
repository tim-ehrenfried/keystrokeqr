import AppIntents

// StartScanIntent selbst liegt in Shared/StartScanIntent.swift und ist
// Mitglied beider Targets (App + Widget-Extension) — siehe Hinweis dort.

/// Stellt die deutschen Siri-/Spotlight-Phrasen bereit (nur App-Target).
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
