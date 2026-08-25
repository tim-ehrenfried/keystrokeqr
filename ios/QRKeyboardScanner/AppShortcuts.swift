import AppIntents

// StartScanIntent selbst liegt in Shared/StartScanIntent.swift und ist
// Mitglied beider Targets (App + Widget-Extension) — siehe Hinweis dort.

/// Stellt die Siri-/Spotlight-Phrasen bereit (nur App-Target). Basissprache
/// Englisch; `\(.applicationName)` löst zum Anzeigenamen „KeystrokeQR" auf.
struct QRKeyboardScannerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: [
                "Scan QR Code with \(.applicationName)",
                "Scan a QR code with \(.applicationName)",
                "Start the scanner in \(.applicationName)",
                "Scan a barcode with \(.applicationName)"
            ],
            shortTitle: "Scan QR Code",
            systemImageName: "qrcode.viewfinder"
        )
    }
}
