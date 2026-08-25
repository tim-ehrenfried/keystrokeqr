# Schritt-für-Schritt: Vom Apple-Developer-Account bis zum laufenden System

Diese Anleitung führt einmal komplett durch: Account aktivieren → iOS-App aufs iPhone → Mac-App einrichten → Sperrbildschirm-Schnellstart.

## 0. Apple-Developer-Account (in Bearbeitung)

1. Nach dem Kauf dauert die Aktivierung meist **wenige Stunden bis 48 h**. Du bekommst eine Bestätigungs-Mail „Welcome to the Apple Developer Program".
2. Status prüfen: [developer.apple.com/account](https://developer.apple.com/account) → oben muss „Apple Developer Program" (nicht mehr „Pending") stehen.
3. **Wichtig:** Bis zur Aktivierung kannst du trotzdem schon alles mit dem *kostenlosen* Personal Team aufs iPhone deployen — die App läuft dann nur 7 Tage und muss neu installiert werden. Mit aktiviertem Account gilt das Provisioning **1 Jahr**.

## 1. Xcode mit dem Account verbinden

1. Xcode öffnen → Menü **Xcode → Settings… → Accounts**.
2. Links unten **+** → **Apple ID** → mit der Apple-ID des Dev-Accounts anmelden.
3. Nach der Aktivierung erscheint rechts dein Team mit dem Zusatz **„(Company/Individual)"** statt „(Personal Team)".

## 2. iOS-App aufs iPhone bringen

1. Projekt öffnen:
   ```bash
   open /Users/timehrenfried/DEV/TOOLS/qr-keyboard/ios/QRKeyboardScanner.xcodeproj
   ```
2. Im Navigator das Projekt **QRKeyboardScanner** anklicken → Target **QRKeyboardScanner** → Tab **Signing & Capabilities**:
   - ✅ *Automatically manage signing*
   - **Team**: dein Developer-Team wählen.
   - Meldet Xcode eine Bundle-ID-Kollision, die ID leicht abwandeln (z. B. `de.timehrenfried.qr-keyboard-scanner2`).
   - Dasselbe **auch für das Widget-Target `QRKeyboardScannerWidgets`** (gleiches Team; Bundle-ID der Extension muss mit der App-ID beginnen).
3. iPhone per **USB-Kabel** an den Mac (beim ersten Mal), am iPhone **„Diesem Computer vertrauen"** bestätigen.
4. Am iPhone den **Entwicklermodus** aktivieren: *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* → einschalten → Neustart → nach dem Neustart bestätigen. (Der Schalter erscheint erst, wenn das iPhone einmal mit Xcode verbunden war.)
5. In Xcode oben in der Geräteleiste dein iPhone als Ziel wählen → **▶ Run** (⌘R). Xcode installiert und startet die App.
   - Danach geht's auch kabellos: solange iPhone + Mac im selben WLAN sind, taucht das Gerät weiter in Xcode auf.
6. Beim ersten Start auf dem iPhone zwei Dialoge **erlauben**:
   - **Kamera** (für den Scanner)
   - **Lokales Netzwerk** (für die Bonjour-Suche nach dem Mac — ohne das findet die App den Mac nicht!)
   - Falls versehentlich abgelehnt: *Einstellungen → Apps → QR Keyboard Scanner* → beides einschalten.

## 3. Mac-App bauen, starten, freischalten

1. Bauen und starten:
   ```bash
   cd /Users/timehrenfried/DEV/TOOLS/qr-keyboard/macos && make run
   ```
   (Mit aktivem Dev-Account optional stabil signieren, dann übersteht die Berechtigung auch Rebuilds:
   `make app SIGN_IDENTITY="Apple Development: <dein Name> (TEAMID)"` — Identitäten anzeigen mit `security find-identity -v -p codesigning`.)
2. In der Menüleiste erscheint das QR-Symbol. Menü öffnen → Accessibility-Status prüfen.
3. **Bedienungshilfen freischalten** (zwingend fürs Tippen):
   *Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen* → Schalter bei **„QR Keyboard Host"** aktivieren (fehlt der Eintrag: unten **+** → `macos/dist/QR Keyboard Host.app` auswählen).
4. Fragt macOS (ab macOS 15) nach **„Lokales Netzwerk"** für die App → erlauben.
5. Firewall aktiv? *Systemeinstellungen → Netzwerk → Firewall → Optionen* → eingehende Verbindungen für „QR Keyboard Host" erlauben.

## 4. Einmaliges Koppeln (Pairing, seit v0.6.0 Pflicht)

Seit v0.6.0 ist die Verbindung Ende-zu-Ende verschlüsselt und **gekoppelt** —
ein iPhone muss dem Mac einmalig bekannt gemacht werden, bevor es Tastatureingaben
auslösen kann (Details: [PROTOCOL-v2.md](PROTOCOL-v2.md), Sicherheitsbewertung:
[../SECURITY.md](../SECURITY.md)).

1. Mac und iPhone im **selben WLAN** (WARP/VPN am Mac kann mDNS stören — im Zweifel kurz deaktivieren).
2. Am Mac in der Menüleiste das QR-Symbol öffnen → **„Gerät koppeln…“**. Ein
   Fenster mit einem **6-stelligen Code** erscheint (90 Sekunden gültig).
3. Am iPhone die App öffnen. Wird der Mac zum ersten Mal gefunden, erscheint
   automatisch der Pairing-Screen: Code eintippen → **„Koppeln“**.
4. Nach erfolgreichem Pairing verbindet sich die App automatisch neu — die
   Status-Kapsel wechselt auf **„Verbunden mit \<Mac-Name\>"**; das Mac-Menü
   zeigt „1 gekoppelt · 1 verbunden“ und listet das iPhone unter den
   gekoppelten Geräten (mit „Entfernen“-Option).
5. Das Pairing ist **einmalig** — bei künftigen Starts verbindet sich die App
   automatisch mit dem gespeicherten Schlüssel, ohne erneuten Code.

## 5. Erster End-to-End-Test

1. Am Mac den Cursor in ein Textfeld setzen (TextEdit reicht), am iPhone einen QR-Code scannen → Text erscheint sofort am Cursor. Toggles **Auto-Enter/Auto-Tab** nach Bedarf.

## 6. Schnellstart vom Sperrbildschirm

Die App bringt ein Lock-Screen-Widget, eine iOS-18-Steuerung und einen Kurzbefehl mit:

- **Sperrbildschirm-Widget:** Sperrbildschirm gedrückt halten → **Anpassen** → Sperrbildschirm → Widget-Bereich unter der Uhr antippen → **QR Keyboard Scanner** → Widget hinzufügen. Antippen startet direkt den Scanner.
- **iOS 18 – Schnelltasten unten ersetzen:** Beim Anpassen des Sperrbildschirms die Taschenlampen-/Kamera-Taste antippen (−), dann **+** → Steuerung **„QR scannen"** wählen. Auch im **Kontrollzentrum** platzierbar (Kontrollzentrum öffnen → + oben links → Steuerung hinzufügen).
- **Action Button (iPhone 15 Pro / 16):** *Einstellungen → Action Button* → **Kurzbefehl** → „Scanne QR-Code" wählen.
- **Siri/Spotlight:** „Scanne QR-Code" funktioniert direkt als Siri-Phrase und in der Kurzbefehle-App als Baustein für eigene Automationen.

## Troubleshooting

| Problem | Lösung |
|---|---|
| iPhone findet den Mac nicht | Gleiches WLAN? Lokales-Netzwerk-Berechtigung auf **beiden** Geräten? VPN/WARP am Mac aus? Firewall-Freigabe? |
| Mac tippt nicht | Bedienungshilfen-Berechtigung fehlt/verfallen → Eintrag in den Systemeinstellungen entfernen und neu erteilen (passiert nach Rebuilds bei ad-hoc-Signatur). |
| „Untrusted Developer" am iPhone | Nur beim kostenlosen Personal Team: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → Entwickler vertrauen. |
| App verschwindet nach 7 Tagen | Kostenloses Team im Einsatz — nach Account-Aktivierung in Xcode das richtige Team wählen und neu installieren. |
| „Bitte Mac-App aktualisieren" | Der gefundene Mac läuft noch mit v1 (vor 0.6.0) — Mac-App neu bauen/installieren. |
| Pairing schlägt mit „Falscher Code" fehl | Code ist nur 90 s **und nur ein Versuch** gültig — am Mac im Menü „Gerät koppeln…" einen neuen Code erzeugen. |
| Nach Pairing weiterhin „not_paired" | Das Gerät wurde am Mac zwischenzeitlich entfernt (Menü → Gerät → „Entfernen") — App bietet dann automatisch erneutes Pairing an. |
