import SwiftUI

/// In-App-Anleitung (Sheet), deutsch.
struct HelpView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPairedMacs = false

    /// Version + Build dynamisch aus dem Bundle, z. B. „0.5.0 (1)".
    private static var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

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

                Section("Einmaliges Koppeln (Pairing)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seit Version 0.6.0 ist die Verbindung **verschlüsselt und gekoppelt** — nur ausdrücklich gekoppelte iPhones können Tastatureingaben auf dem Mac auslösen.")
                        Text("1. Am Mac im Menü das QR-Symbol öffnen → **„Gerät koppeln…“**.")
                        Text("2. Der Mac zeigt einen **6-stelligen Code** (90 Sekunden gültig).")
                        Text("3. Findet das iPhone einen neuen Mac, erscheint automatisch der Pairing-Screen — Code eintippen, **Koppeln** antippen.")
                        Text("4. Das Pairing ist **einmalig**: Der gemeinsame Schlüssel wird sicher im Schlüsselbund gespeichert und bei jeder künftigen Verbindung automatisch verwendet.")
                    }
                    .font(.callout)

                    Button {
                        showPairedMacs = true
                    } label: {
                        Label("Gekoppelte Macs verwalten", systemImage: "lock.desktopcomputer")
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
                        Text("• **Tippen** auf den Sucher fokussiert auf die Stelle (gelber Rahmen), **Auf-/Zuziehen** mit zwei Fingern zoomt. Die Kamera wechselt bei nahen Codes automatisch die Linse (Makro auf neueren iPhones).")
                        Text("• **Jeder Code wird nur einmal automatisch getippt.** Wird derselbe Code erneut gescannt, sendet die App nicht automatisch — stattdessen erscheint unten der gelbe Auslöser **„Erneut senden“**, der den Code bewusst noch einmal überträgt.")
                        Text("• **Verlauf leeren** (⟲ in der Bedienleiste) vergisst alle bereits gesendeten Codes; beim App-Neustart passiert das automatisch.")
                    }
                    .font(.callout)
                }

                Section("Schnellstart vom Sperrbildschirm") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("**Sperrbildschirm-Widget:** Sperrbildschirm gedrückt halten → **Anpassen** → Sperrbildschirm wählen → Widget-Bereich antippen → **QR-Keyboard Scanner** hinzufügen. Antippen startet den Scanner direkt.")
                        Text("**iOS 18 – Schnelltasten:** Beim Anpassen des Sperrbildschirms eine der beiden unteren Schnelltasten (Taschenlampe/Kamera) durch **„QR-Code scannen“** ersetzen. Dieselbe Steuerung lässt sich auch ins **Kontrollzentrum** legen.")
                        Text("**Action Button (iPhone 15 Pro und neuer):** Einstellungen → **Action Button** → **Kurzbefehl** → Aktion **„QR-Code scannen“** wählen.")
                        Text("**Siri/Spotlight:** „Scanne QR-Code mit QR-Keyboard Scanner“ sagen oder in Spotlight nach „Scannen“ suchen.")
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
                        Divider()
                        Text("**„Bitte Mac-App aktualisieren“?**")
                        Text("• Der gefundene Mac läuft noch mit der alten, unverschlüsselten Version. Auf dem Mac die neue Version installieren (mind. 0.6.0).")
                        Divider()
                        Text("**Pairing schlägt fehl / Code falsch?**")
                        Text("• Codes sind nur 90 Sekunden gültig und **einmalig** — am Mac im Menü „Gerät koppeln…“ einen neuen Code erzeugen und zügig eintippen.")
                    }
                    .font(.callout)
                }

                Section("Über") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QR-Keyboard Scanner")
                            .font(.headline)
                        Text("Version \(Self.appVersionString)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("© 2026 Tim Ehrenfried")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let mailURL = URL(string: "mailto:mail@tim-ehrenfried.de") {
                        Link(destination: mailURL) {
                            Label("mail@tim-ehrenfried.de", systemImage: "envelope")
                        }
                    }
                    if let repoURL = URL(string: "https://github.com/tim-ehrenfried/qr-keyboard") {
                        Link(destination: repoURL) {
                            Label("Open Source auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }
            }
            .navigationTitle("Hilfe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showPairedMacs) {
                PairedMacsView(connectionManager: connectionManager)
            }
        }
    }
}

#Preview {
    HelpView(connectionManager: ConnectionManager())
}
