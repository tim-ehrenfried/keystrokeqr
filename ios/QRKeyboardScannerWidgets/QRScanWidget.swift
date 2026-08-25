import WidgetKit
import SwiftUI

/// Statisches Widget: öffnet die App via `keystrokeqr://scan` direkt im Scanner.
/// Familien: Sperrbildschirm (accessoryCircular/-Rectangular) + systemSmall
/// für den Homescreen.
struct QRScanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QRScanWidget", provider: ScanProvider()) { _ in
            QRScanWidgetView()
                .widgetURL(URL(string: "keystrokeqr://scan"))
        }
        .configurationDisplayName("Scan QR Code")
        .description("Opens the KeystrokeQR scanner directly — even from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

// MARK: - Timeline (statisch)

struct ScanEntry: TimelineEntry {
    let date: Date
}

struct ScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanEntry {
        ScanEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScanEntry) -> Void) {
        completion(ScanEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanEntry>) -> Void) {
        completion(Timeline(entries: [ScanEntry(date: .now)], policy: .never))
    }
}

// MARK: - Ansicht

struct QRScanWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scan")
                        .font(.headline)
                    Text("QR → type on Mac")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color.clear }
        default: // .systemSmall
            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 42, weight: .medium))
                Text("Scan")
                    .font(.headline)
            }
            .foregroundStyle(.primary)
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
    }
}
