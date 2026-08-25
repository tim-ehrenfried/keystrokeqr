import SwiftUI

/// Sichtbares Scan-Fenster über dem Kamerabild: der 1:1-Ausschnitt
/// (`ScanRegion`) bleibt komplett klar, der Rest wird abgedunkelt, aber
/// durchscheinend (Even-Odd-Pfad). Dazu dezente helle Eckklammern im
/// Viewfinder-Stil (Markengelb). Rein dekorativ und nicht interaktiv —
/// Tap-to-Focus/Pinch-to-Zoom laufen auf dem darunterliegenden Preview weiter.
struct ScanWindowOverlay: View {
    /// Markengelb #FFD60A.
    static let accent = Color(red: 1.0, green: 0.839, blue: 0.039)

    var body: some View {
        GeometryReader { geo in
            let window = ScanRegion.rect(in: geo.size)
            ZStack {
                // Abdunkelung außen: Vollfläche minus abgerundetes Fenster.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRoundedRect(
                        in: window,
                        cornerSize: CGSize(width: ScanRegion.cornerRadius, height: ScanRegion.cornerRadius),
                        style: .continuous
                    )
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                // Eckklammern entlang der vier abgerundeten Ecken.
                cornerBrackets(in: window)
                    .stroke(
                        Self.accent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Vier Eckklammern: kurzes Stück Kante — Viertelbogen — kurzes Stück Kante.
    private func cornerBrackets(in rect: CGRect) -> Path {
        let radius = ScanRegion.cornerRadius
        let arm: CGFloat = 22 // sichtbare Schenkellänge über den Bogen hinaus

        var path = Path()
        // Oben links
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius + arm, y: rect.minY))
        // Oben rechts
        path.move(to: CGPoint(x: rect.maxX - radius - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius + arm))
        // Unten rechts
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius - arm, y: rect.maxY))
        // Unten links
        path.move(to: CGPoint(x: rect.minX + radius + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius - arm))
        return path
    }
}

#Preview {
    ZStack {
        Color.gray
        ScanWindowOverlay()
    }
    .ignoresSafeArea()
}
