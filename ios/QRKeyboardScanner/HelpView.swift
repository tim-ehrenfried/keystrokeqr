import SwiftUI

/// In-App-Anleitung (Sheet), deutsch.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Voraussetzungen") {
                    Label {
                        Text("iPhone und Mac sind im **gleichen WLAN** (bzw. gleichen lokalen Netzwerk).")
                    } icon: {
                        Image(systemName: "wifi")
                    }
                    Label {
                        Text("Die **QR-Keyboard Mac-App läuft** auf dem Mac (Menüleisten-Symbol sichtbar).")
                    } icon: {
                        Image(systemName: "desktopcomputer")
                    }
                    Label {
                        Text("Der Mac hat die **Bedienungshilfen-Berechtigung** erteilt — nur damit kann er Tastatureingaben simulieren.")
                    } icon: {
                        Image(systemName: "accessibility")
                    }
                }

                Section("Bedienungshilfen auf dem Mac erlauben") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Auf dem Mac **Systemeinstellungen** öffnen.")
                        Text("2. **Datenschutz & Sicherheit → Bedienungshilfen** wählen.")
                        Text("3. **QR-Keyboard** in der Liste aktivieren (ggf. über „+“ hinzufügen).")
                        Text("4. Falls die App schon lief: einmal beenden und neu starten.")
                    }
                    .font(.callout)
                }

                Section("Bedienung") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Die App sucht automatisch nach Macs und verbindet sich mit dem ersten gefundenen. Werden mehrere gefunden, erscheint eine Auswahl.")
                        Text("• Kamera auf einen QR- oder Barcode richten — bei Erkennung vibriert das iPhone kurz, der Sucher friert 1 Sekunde ein und der Text wird sofort am Mac „getippt“.")
                        Text("• **Auto-Enter**: Nach dem Text wird zusätzlich die Return-Taste gesendet.")
                        Text("• **Auto-Tab**: Nach dem Text wird zusätzlich die Tab-Taste gesendet (bei beiden: erst Tab, dann Enter).")
                        Text("• Der zuletzt gescannte Text wird unten angezeigt.")
                    }
                    .font(.callout)
                }

                Section("Problembehebung") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Kein Mac gefunden?**")
                        Text("• Prüfe, ob das iPhone der App den Zugriff auf das **lokale Netzwerk** erlaubt: Einstellungen → Apps → QR-Keyboard Scanner → Lokales Netzwerk.")
                        Text("• Prüfe, ob iPhone und Mac wirklich im selben Netz sind (kein Gäste-WLAN, kein VPN mit blockiertem lokalen Verkehr).")
                        Text("• Die **macOS-Firewall** darf eingehende Verbindungen für QR-Keyboard nicht blockieren: Systemeinstellungen → Netzwerk → Firewall → Optionen.")
                        Divider()
                        Text("**Verbunden, aber es wird nichts getippt?**")
                        Text("• Meist fehlt die Bedienungshilfen-Berechtigung auf dem Mac (siehe oben) — die App zeigt dann einen Hinweis an.")
                        Text("• Stelle sicher, dass am Mac das gewünschte Eingabefeld fokussiert ist.")
                    }
                    .font(.callout)
                }
            }
            .navigationTitle("Hilfe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HelpView()
}
