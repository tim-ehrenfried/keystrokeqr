import SwiftUI

struct KeystrokeQRIcon: View {
    var body: some View {
        ZStack {
            // 1. Hintergrund-Gradient (Mitternachtsblau zu Violett)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.25),
                    Color(red: 0.35, green: 0.15, blue: 0.55)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
            
            // 2. QR-Scanner Sucherrahmen (Neon-Orange)
            Group {
                // Oben Links
                Path { path in
                    path.move(to: CGPoint(x: 110, y: 150))
                    path.addLine(to: CGPoint(x: 110, y: 110))
                    path.addLine(to: CGPoint(x: 150, y: 110))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                
                // Oben Rechts
                Path { path in
                    path.move(to: CGPoint(x: 250, y: 110))
                    path.addLine(to: CGPoint(x: 290, y: 110))
                    path.addLine(to: CGPoint(x: 290, y: 150))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                
                // Unten Links
                Path { path in
                    path.move(to: CGPoint(x: 110, y: 250))
                    path.addLine(to: CGPoint(x: 110, y: 290))
                    path.addLine(to: CGPoint(x: 150, y: 290))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                
                // Unten Rechts
                Path { path in
                    path.move(to: CGPoint(x: 250, y: 290))
                    path.addLine(to: CGPoint(x: 290, y: 290))
                    path.addLine(to: CGPoint(x: 290, y: 250))
                }
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            }
            .shadow(color: Color.orange.opacity(0.4), radius: 8)
            
            // 3. Strahlend weißer Text-Cursor in der Mitte
            Capsule()
                .fill(Color.white)
                .frame(width: 14, height: 110)
                .shadow(color: Color.white.opacity(0.6), radius: 12)
        }
        .frame(width: 400, height: 400)
        // Erzeugt die offizielle, abgerundete Apple-App-Icon-Form
        .clipShape(RoundedRectangle(cornerRadius: 88, style: .continuous))
    }
}

// ====================================================
// WICHTIG: Dieses Makro aktiviert die Xcode-Vorschau!
// ====================================================
#Preview {
    KeystrokeQRIcon()
        .padding(40)
        .background(Color(.systemBackground))
}

