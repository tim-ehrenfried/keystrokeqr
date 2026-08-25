# KeystrokeQR Host (macOS)

Menüleisten-App des Open-Source-Systems **KeystrokeQR**: empfängt QR-Scans vom
iPhone (per WebSocket im lokalen Netz, Bonjour-Discovery) und tippt den
gescannten Text als echte Tastaturanschläge in das aktuell fokussierte Fenster —
optional gefolgt von Tab und/oder Enter.

Protokoll: siehe [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md)
(Bonjour `_keystrokeqr._tcp`, Port 8080 mit Fallback auf freien Port,
JSON-Nachrichten über WebSocket). Seit v0.6.0 ist die Verbindung gekoppelt
(einmaliges OTP-Pairing) und Ende-zu-Ende verschlüsselt — siehe
[`../SECURITY.md`](../SECURITY.md). Namen/IDs sind in
[`../docs/BRANDING.md`](../docs/BRANDING.md) verbindlich festgelegt.

- **Bundle-ID:** `de.timehrenfried.keystrokeqr.host`
- **Bonjour-Service-Typ:** `_keystrokeqr._tcp` (muss exakt zum iOS-Client passen)
- **Version:** 0.10.0

## Voraussetzungen

- macOS 13 (Ventura) oder neuer
- Xcode bzw. Swift-Toolchain (Swift 5.9+; getestet mit Swift 6.3)
- Für Icon/DMG-Erzeugung: ImageMagick 7 (`magick`) sowie `sips`/`iconutil`
  (Teil von macOS)

## Bauen

```sh
cd macos
make app
```

Das erzeugt das App-Bundle **`dist/KeystrokeQR Host.app`** (Release-Build,
ad-hoc-signiert) inklusive Lokalisierungen (`Contents/Resources/en.lproj` +
`de.lproj`). Das Bundle ist wichtig, damit macOS die
Bedienungshilfen-Berechtigung sauber **pro App** zuordnen kann.

Weitere Targets:

| Target       | Wirkung                                                   |
| ------------ | --------------------------------------------------------- |
| `make build` | nur das Release-Binary bauen                              |
| `make icon`  | App-Icon `Support/AppIcon.icns` neu erzeugen (ImageMagick) |
| `make app`   | App-Bundle unter `dist/` erzeugen                         |
| `make dmg`   | gestyltes `dist/KeystrokeQR-Host.dmg` bauen               |
| `make run`   | Bundle bauen und starten                                  |
| `make clean` | Build-Artefakte, `dist/` und Hintergrundbild entfernen    |

Mit Apple-Developer-Account statt ad-hoc signieren:

```sh
make app SIGN_IDENTITY="Developer ID Application: Tim Ehrenfried (TEAMID)"
```

(verfügbare Identitäten: `security find-identity -v -p codesigning`)

## DMG-Installer (`make dmg`)

`make dmg` erzeugt ein gestyltes Disk-Image **`dist/KeystrokeQR-Host.dmg`** mit
Hintergrundbild (dunkel, „KeystrokeQR Host" + Pfeil „→ In Programme ziehen"),
dem App-Icon links und einem **/Applications-Symlink** rechts.

- Ist `create-dmg` (Homebrew: `brew install create-dmg`) installiert, wird es
  bevorzugt genutzt und setzt Fenstergröße + Icon-Positionen direkt.
- Sonst greift der `hdiutil`-Fallback. Er legt App, `/Applications`-Symlink und
  Hintergrundbild (`.background/background.png`) ins Volume und **versucht** das
  Feinstyling (Icon-Positionen, Fenster) per Finder-AppleScript.

> **Einschränkung (Headless/CI):** Das Finder-AppleScript-Styling benötigt eine
> GUI-/Finder-Session. Läuft `make dmg` ohne (z. B. in GitHub Actions), wird das
> Styling übersprungen — das DMG ist trotzdem voll funktionsfähig (App +
> `/Applications`-Symlink + Hintergrundbild), nur ohne vorgesetzte
> Icon-Koordinaten. Für ein pixelgenau gestyltes DMG `make dmg` lokal bzw. mit
> installiertem `create-dmg` ausführen.

Das DMG wird ad-hoc bzw. mit `SIGN_IDENTITY` signiert (Notarisierung ist nicht
Teil dieses Targets).

## Internationalisierung (i18n)

Alle nutzersichtbaren Host-Strings (Menüpunkte inkl. Tippgeschwindigkeit,
Statuszeilen, Pairing-Fenster inkl. Countdown/Hinweisen sowie das Onboarding-/
Willkommensfenster) sind lokalisiert. **Basissprache/Development Language ist
Englisch (`en`)**, zusätzlich Deutsch (`de`).

- Quellen: `Support/en.lproj/Localizable.strings` und
  `Support/de.lproj/Localizable.strings` (plus `InfoPlist.strings` für die
  Berechtigungsdialoge). `make app` kopiert sie nach
  `Contents/Resources/<lang>.lproj/`.
- Im Code läuft der Zugriff über die Hilfsfunktion `L(_:)`
  (`NSLocalizedString`, Tabelle `Localizable`) — siehe
  `Sources/QRKeyboardHost/Localization.swift`.
- Die angezeigte Sprache folgt der Systemeinstellung des Nutzers.

## Starten

```sh
make run
# oder:
open "dist/KeystrokeQR Host.app"
```

Die App erscheint als QR-Symbol in der Menüleiste (kein Dock-Icon). Das Menü ist
seit v0.9.0 **schlank** und dient vor allem dem Blick auf den Status:

- **Kopplungs-/Verbindungsstatus** („Kein Gerät gekoppelt" / „N gekoppelt · M verbunden")
- **Port und Bonjour-Dienstname** (der Hostname des Macs)
- **Bedienungshilfen-Status** (✓/✗) — auf einen Blick erkennbar, ob alles bereit ist
- **„KeystrokeQR öffnen…"** — öffnet das zentrale Kontrollzentrum (s. u.)
- **Beenden**

Optional kann die App zu **Anmeldeobjekte** hinzugefügt werden
(Systemeinstellungen → Allgemein → Anmeldeobjekte), damit sie automatisch
startet.

## Kontrollzentrum (KeystrokeQR-Panel)

Seit **v0.9.0** liegen alle Funktionen gebündelt in einem gestylten Fenster im
dunklen KeystrokeQR-Look (statt vieler Menüpunkte). Öffnen über den Menüpunkt
**„KeystrokeQR öffnen…"**. Das Panel läuft als normales, fokussierbares Fenster,
während die App weiterhin reine Menüleisten-App (`.accessory`) bleibt.

Seit **v0.10.0** ist es **ein einziges Fenster** mit interner Navigation: „Hilfe"
und „Über" werden als Unterseiten in denselben Rahmen geschoben (kein Scroll —
das Fenster öffnet für jede Seite genau so groß wie ihr Inhalt und passt seine
Größe beim Navigieren animiert an). Oben links ein **Zurück-Button** (nur auf den
Unterseiten), oben rechts auf gleicher Höhe ein dezenter grauer
**„Einführung"-Button**. Abschnitte der Home-Ansicht:

- **Verbindung** — Bonjour-Dienstname, Port und „N gekoppelt · M verbunden".
- **Bedienungshilfen** — großes grünes ✓ „Aktiviert" bzw. rotes ✗ „Nicht
  aktiviert" mit kurzer Erklärung und Button „Bedienungshilfen öffnen…". Der
  Status ist **live**: solange das Panel offen (und aktiv) ist, pollt es
  `AXIsProcessTrusted()` alle ~1,5 s und aktualisiert zusätzlich sofort, sobald
  das Fenster den Fokus bekommt — nach dem Erteilen der Berechtigung erscheint
  das ✓ also ohne App-Neustart.
- **Gekoppelte Geräte** — Liste (Name + Kopplungsdatum) mit „Entfernen" je Gerät
  und „Gerät koppeln…" (öffnet das bestehende Pairing-Fenster). „Entfernen"
  löscht den gemeinsamen Schlüssel (PSK) aus der Keychain **und** trennt sofort
  eine evtl. laufende Sitzung dieses Geräts, damit der Client den Abbruch bemerkt
  und in Neu-Pairing gehen kann (docs/PROTOCOL-v2.md, „Geräteverwaltung").
- **Tippgeschwindigkeit** — Schnell / Normal / Langsam als Segmentumschalter,
  sofort wirksam (s. u.).
- Einstiege zu den Unterseiten **Hilfe** und **Über** (die „Einführung" liegt als
  grauer Button oben rechts).

## Hilfe & Über (Unterseiten)

- **Hilfe** (Button in der Home-Ansicht) schiebt eine Unterseite mit Kurzanleitung
  (Hintergrundbetrieb, Kopplung, Bedienungshilfen, Tippgeschwindigkeit bei viel
  Text), Fehlerbehebung (iPhone findet den Mac nicht → gleiches WLAN/Firewall/VPN;
  es wird nichts getippt → Bedienungshilfen) sowie Links zum
  [GitHub-Repo](https://github.com/tim-ehrenfried/keystrokeqr) und zur
  Dokumentation (als Buttons mit Icon). Zweisprachig (en/de).
- **Über** zeigt App-Name „KeystrokeQR Host", Version/Build **dynamisch aus dem
  Bundle**, „© 2026 Tim Ehrenfried", die MIT-Lizenz und die Links — GitHub,
  „E-Mail schreiben" (mailto:mail@tim-ehrenfried.de) und Dokumentation — als
  **Buttons mit SF-Symbol** (wie in der iOS-App), im dunklen KeystrokeQR-Stil
  (kein NSAboutPanel-Default).

## Willkommen / Onboarding (Erst-Start)

Beim **allerersten Start** zeigt die App einmalig ein gestyltes Willkommens-
fenster: kurz, was die App tut (iPhone scannt → Mac tippt), ein Hinweis auf die
nötige **Bedienungshilfen**-Berechtigung mit Button „Bedienungshilfen öffnen…"
sowie „Gerät koppeln…". Ob es schon gezeigt wurde, merkt sich die App in
UserDefaults (`didCompleteHostOnboarding`). Jederzeit erneut aufrufbar über den
grauen **„Einführung"**-Button oben rechts im KeystrokeQR-Fenster.

## Tippgeschwindigkeit

Das Untermenü **„Tippgeschwindigkeit"** stellt ein, wie zügig empfangener Text
getippt wird (persistiert in UserDefaults, aktuelle Stufe mit Häkchen):

| Stufe    | Verhalten                                                            |
| -------- | ------------------------------------------------------------------- |
| Schnell  | große Chunks, sehr kurze Pause — zügig                              |
| Normal   | Standard (entspricht dem bisherigen Verhalten)                      |
| Langsam  | kleine Chunks, deutlich größere Pause — robust für träge/entfernte  |
|          | Zielfelder (Remote-Sessions), damit sich bei viel Text nichts       |
|          | „verfängt"/verschluckt                                              |

Die Änderung greift sofort für den nächsten Scan.

## Bedienungshilfen-Berechtigung freischalten (erforderlich!)

Damit die App Tastaturanschläge in andere Programme „tippen" darf, braucht sie
die macOS-Berechtigung **Bedienungshilfen** (Accessibility). Ohne diese
Berechtigung beantwortet die App Scans mit dem Fehler `accessibility_denied`.

Schritt für Schritt:

1. **App starten** (`make run`). Beim ersten Scan ohne Berechtigung zeigt
   macOS automatisch einen Hinweis-Dialog an — alternativ direkt über das
   Menü der App: **„Bedienungshilfen öffnen…"**.
2. Es öffnen sich die **Systemeinstellungen → Datenschutz & Sicherheit →
   Bedienungshilfen**.
3. Falls **„KeystrokeQR Host"** bereits in der Liste steht: den **Schalter
   aktivieren**.
4. Falls die App noch nicht in der Liste steht: unten auf **„+"** klicken,
   zum Ordner `macos/dist/` navigieren und **„KeystrokeQR Host.app"**
   auswählen, dann den Schalter aktivieren.
5. Ggf. mit dem Administrator-Passwort bestätigen.
6. Der Bedienungshilfen-Status wird **live** erkannt: Im Kontrollzentrum
   (**„KeystrokeQR öffnen…"**) wechselt die Anzeige nach dem Erteilen innerhalb
   von ~1–2 s auf das grüne ✓ „Aktiviert" — ganz ohne App-Neustart. Auch die
   Menüleiste zeigt beim nächsten Öffnen **„Bedienungshilfen: ✓ erteilt"**.

> **Hinweis nach Updates:** Wird die App neu gebaut (neue Binary/Signatur),
> kann macOS die Berechtigung verwerfen. In dem Fall den Eintrag in
> **Datenschutz & Sicherheit → Bedienungshilfen** entfernen (Minus-Taste)
> und die App wie oben beschrieben **neu hinzufügen** bzw. den Schalter
> erneut aktivieren.

> **Hinweis zum Rebrand (v0.7.0):** Bundle-ID, Keychain-Service und
> Bonjour-Service-Typ haben sich geändert. Bestehende Kopplungen aus v0.6.x
> müssen einmalig **neu** durchgeführt werden (siehe
> [`../docs/BRANDING.md`](../docs/BRANDING.md)).

## Lokales Netzwerk

Ab macOS 15 (Sequoia) kann macOS zusätzlich eine Freigabe für das **lokale
Netzwerk** abfragen — diese ebenfalls erlauben, sonst findet das iPhone den
Mac nicht per Bonjour.

## Funktionsweise (Kurzfassung)

- WebSocket-Server via `Network.framework` (`NWListener` + WebSocket-Options,
  `autoReplyPing`), fester Port **8080**, bei Belegung automatisch ein freier
  Port (der iOS-Client nutzt immer den via Bonjour aufgelösten Port).
- Bonjour-Advertising als `_keystrokeqr._tcp` mit TXT-Record `v=2`.
- Jede Verbindung durchläuft entweder das OTP-Pairing (nur bei geöffnetem
  „Gerät koppeln…"-Fenster) oder den Sitzungs-Handshake für bereits
  gekoppelte Geräte; danach ausschließlich ChaChaPoly-verschlüsselte Frames
  (Curve25519 + HKDF-SHA256, Identität + PSKs in der Keychain, Service
  `de.timehrenfried.keystrokeqr.host`). Details:
  [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md).
- Mehrere iPhones können gleichzeitig verbunden sein; Scans werden strikt
  sequenziell getippt (Reihenfolge: Text → Tab → Enter).
- Text-Injektion erfolgt Unicode-basiert über `CGEvent` und ist damit
  unabhängig vom aktiven Tastaturlayout (auch Emoji und Sonderzeichen).
