import WidgetKit
import SwiftUI
import AppIntents

/// Control Widget (iOS 18+): kann als Sperrbildschirm-Schnelltaste (unten,
/// anstelle von Taschenlampe/Kamera) oder im Kontrollzentrum abgelegt werden.
/// Öffnet die App direkt im Scanner.
///
/// Verwendet den in Shared/ liegenden `StartScanIntent`, der in App UND
/// Extension kompiliert wird — nur so führt das System `openAppWhenRun`
/// zuverlässig aus (im App-Prozess). Bewusst KEIN `OpenURLIntent` mit
/// Custom-URL-Scheme: das ist unter iOS 18.0 fehlerbehaftet (öffnet u. U.
/// den Browser statt der App; erst ab iOS 18.1 behoben).
@available(iOSApplicationExtension 18.0, *)
struct QRScanControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QRScanControl") {
            ControlWidgetButton(action: StartScanIntent()) {
                Label("Scan QR", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("Scan QR Code")
        .description("Opens the KeystrokeQR scanner.")
    }
}
