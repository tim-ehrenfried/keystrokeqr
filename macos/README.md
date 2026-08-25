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
- **Version:** 0.12.0

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
- **Autostart-Status** („Beim Login starten: ✓/✗")
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
**„Einführung"-Button**.

Seit **v0.12.0** ist die Home-Ansicht im **Querformat**: zwei Kartenspalten
nebeneinander (deutlich breiter als hoch, ~786 pt breit) statt einer hohen
schmalen Spalte. Links: Verbindung, Bedienungshilfen, Bestätigen vor dem Tippen.
Rechts: Gekoppelte Geräte, Tippgeschwindigkeit, Beim Login starten. Header und
Fußzeile (Hilfe/Über) spannen über beide Spalten. Das „so groß wie nötig, kein
Scroll"-Prinzip bleibt; Hilfe/Über sind weiterhin schmaler (einspaltig).
Abschnitte der Home-Ansicht:

- **Verbindung** — Bonjour-Dienstname, Port und „N gekoppelt · M verbunden".
- **Bedienungshilfen** — großes grünes ✓ „Aktiviert" bzw. rotes ✗ „Nicht
  aktiviert" mit kurzer Erklärung und Button „Bedienungshilfen öffnen…". Der
  Status ist **live**: solange das Panel offen (und aktiv) ist, pollt es
  `AXIsProcessTrusted()` alle ~1,5 s und aktualisiert zusätzlich sofort, sobald
  das Fenster den Fokus bekommt — nach dem Erteilen der Berechtigung erscheint
  das ✓ also ohne App-Neustart.
- **Gekoppelte Geräte** — Liste (Name + Kopplungsdatum) mit „Umbenennen" und
  „Entfernen" je Gerät und „Gerät koppeln…" (öffnet das bestehende
  Pairing-Fenster). „Entfernen" löscht den gemeinsamen Schlüssel (PSK) aus der
  Keychain **und** trennt sofort eine evtl. laufende Sitzung dieses Geräts, damit
  der Client den Abbruch bemerkt und in Neu-Pairing gehen kann
  (docs/PROTOCOL-v2.md, „Geräteverwaltung"). Ist noch nichts gekoppelt, zeigt die
  Karte einen Empty-State („Noch kein Gerät gekoppelt – ‚Gerät koppeln…' wählen.").
- **Tippgeschwindigkeit** — Schnell / Normal / Langsam als Segmentumschalter,
  sofort wirksam (s. u.).
- **Bestätigen vor dem Tippen** — Schalter (Default AUS); s. u.
- **Beim Login starten** — Schalter mit Live-Registrierungsstatus (s. u.).
- Einstiege zu den Unterseiten **Hilfe** und **Über** (die „Einführung" liegt als
  grauer Button oben rechts).

Alle Panel-Bedienelemente tragen **Accessibility-Labels/-Rollen** für VoiceOver
(Schalter, Segmentumschalter, Geräte-Zeilen inkl. „Umbenennen"/„Entfernen",
Statussymbol der Bedienungshilfen).

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

## „✓ Getippt"-HUD

Nach jeder **erfolgreichen** Keystroke-Injektion blendet die App kurz (~0,9 s)
ein dezentes, sich selbst ausblendendes HUD „✓ Getippt" ein. Seit **v0.12.0**
erscheint es **unten mittig** — ca. 20 % der sichtbaren Bildschirmhöhe über der
Unterkante (`NSScreen.main.visibleFrame`), nicht mehr oben. Der Look ist modern
und klar zum dunklen KeystrokeQR-Design passend: eine **solide dunkle,
abgerundete Karte** mit dezentem Rahmen und weichem Schatten (kein
verwaschener Blur/`NSVisualEffectView` mehr), scharfer heller Text und ein
Häkchen im **Marken-Gelb (#FFD60A)** als gerendertes SF-Symbol. Weiche
Ein-/Ausblendung.

Es dient nur als Rückmeldung und ist so gebaut, dass es **niemals den
Tastaturfokus stiehlt** (sonst bräche die Eingabe ins Zielfenster ab): ein
randloses, **nicht-aktivierendes** `NSPanel` (`.nonactivatingPanel`,
`isFloatingPanel`, `level = .statusBar`, `ignoresMouseEvents`,
`hidesOnDeactivate = false`), das ausschließlich per `orderFrontRegardless()`
gezeigt wird — nie `makeKey`/`activate`. Bei schnellen Folge-Scans wird dasselbe
Panel wiederverwendet und nur der Ausblend-Timer neu gesetzt (kein Stapeln).

## Bestätigen vor dem Tippen

Im Kontrollzentrum lässt sich der Modus **„Bestätigen vor dem Tippen"**
aktivieren (Default **AUS**; persistiert in UserDefaults). Ist er an, wird ein
eingehender Scan **nicht sofort** getippt: Stattdessen erscheint ein
nicht-aktivierendes Panel mit einer gekürzten **Vorschau** des Texts (plus
Zeichenzahl und ob danach Tab/Enter folgt) und den Buttons **„Tippen"** /
**„Verwerfen"**.

Damit der Text zuverlässig im ursprünglichen Zielfeld landet, merkt sich die App
**vor** dem Anzeigen die gerade fokussierte Fremd-App
(`NSWorkspace.shared.frontmostApplication`). Bei „Tippen" wird zuerst diese App
wieder aktiviert, kurz gewartet und **dann** getippt; „Verwerfen" tippt nichts.
Der Normalpfad (Modus AUS) bleibt unverändert — sofortiges Tippen. Mehrere
schnell eintreffende Scans werden serialisiert (ein Panel nach dem anderen).

## Gerät umbenennen

In der Geräteliste bietet jede Zeile neben „Entfernen" ein **„Umbenennen"** an
(kleiner Dialog mit vorbefülltem Namensfeld). Der neue Name wird im
Keychain-Geräteeintrag persistiert (`CryptoManager.renameDevice(_:to:)`); ein
leerer Name ist unzulässig. PSK, Public Key und Kopplungsdatum bleiben unberührt.

## Beim Login starten

Über den Schalter **„Beim Login starten"** kann die App als Anmeldeobjekt
registriert werden (`SMAppService.mainApp`, macOS 13+). Der Schalter zeigt den
**echten Registrierungsstatus** und behandelt Fehler freundlich; verlangt macOS
eine Freigabe, weist ein Hinweis auf **Systemeinstellungen › Allgemein ›
Anmeldeobjekte** hin. Der Menüleisten-Eintrag spiegelt den Zustand
(„Beim Login starten: ✓/✗").

> **Hinweis:** `SMAppService` wirkt zuverlässig nur aus einer **installierten**
> `.app` (z. B. in `/Applications`). Aus einem nackten SPM-Binary ohne Bundle
> kann die Registrierung fehlschlagen — die Logik liest den Status trotzdem
> korrekt und funktioniert in der ausgelieferten App.

## Tests (`swift test`)

Die sicherheits-/protokollkritische Kernlogik ist mit XCTest abgedeckt
(Testtarget `QRKeyboardHostTests` unter `Tests/QRKeyboardHostTests/`,
`swift test`):

- **HKDF-Ableitungen** (`CryptoCore`): PSK/Confirm/Session-Key mit den exakten
  Salt-/Info-Strings aus docs/PROTOCOL-v2.md — Determinismus, beidseitige
  Übereinstimmung, unterschiedliche Inputs ⇒ unterschiedliche Keys.
- **Pairing-HMAC**: korrekter OTP verifiziert, falscher nicht; konstante-Zeit-
  Vergleich (`HMAC.isValidAuthenticationCode`).
- **ChaChaPoly-Frame** (`SecureFrame`): seal→open-Roundtrip, Nonce =
  Richtungspräfix ‖ big-endian seq, Replay-/Monotonie-Logik, getamperter
  Ciphertext/Tag schlägt fehl.
- **Messages** (Codable): scan/ack/pair_*/session_*/enc — Feldnamen exakt.
- **Payload-Limit**: 8192 UTF-16 (`ScanServer.isTextWithinLimit`), inkl.
  Surrogatpaar-Zählung.
- **TypingSpeed-Mapping**: Chunk-Größe/Pause je Stufe.

Um die Logik ohne Netzwerk/UI testbar zu machen, wurden die reinen
Krypto-Ableitungen in `CryptoCore` und die Längen-Grenzlogik in eine statische
Funktion extrahiert (kein Verhaltenswechsel — `CryptoManager`/`ScanServer`
delegieren dorthin).

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
