import WidgetKit
import SwiftUI

@main
struct QRKeyboardScannerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QRScanWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            QRScanControls().body
        }
    }
}

/// Eigene Bundle-Ebene für iOS-18-only Control Widgets, damit die
/// Verfügbarkeits-Verzweigung im WidgetBundleBuilder sauber typisiert.
@available(iOSApplicationExtension 18.0, *)
struct QRScanControls: WidgetBundle {
    var body: some Widget {
        QRScanControlWidget()
    }
}
