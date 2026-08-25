import WidgetKit
import SwiftUI
import AppIntents

/// Control Widget (iOS 18+): kann als Sperrbildschirm-Schnelltaste (unten,
/// anstelle von Taschenlampe/Kamera) oder im Kontrollzentrum abgelegt werden.
/// Öffnet die App direkt im Scanner.
@available(iOSApplicationExtension 18.0, *)
struct QRScanControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QRScanControl") {
            ControlWidgetButton(action: StartScanControlIntent()) {
                Label("QR scannen", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("QR-Code scannen")
        .description("Öffnet den QR-Keyboard-Scanner.")
    }
}

/// Intent-Variante fürs Control Widget: öffnet die App und routet über den
/// Deep-Link `qrkeyboard://scan` direkt in den Scanner (OpenURLIntent).
@available(iOS 18.0, *)
struct StartScanControlIntent: AppIntent {
    static let title: LocalizedStringResource = "QR-Code scannen"
    static let description = IntentDescription("Öffnet den QR-Keyboard-Scanner.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "qrkeyboard://scan")!))
    }
}
