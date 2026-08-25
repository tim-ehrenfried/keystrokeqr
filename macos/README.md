# QR Keyboard Host (macOS)

Menüleisten-App des Open-Source-Systems **QR-Keyboard**: empfängt QR-Scans vom
iPhone (per WebSocket im lokalen Netz, Bonjour-Discovery) und tippt den
gescannten Text als echte Tastaturanschläge in das aktuell fokussierte Fenster —
optional gefolgt von Tab und/oder Enter.

Protokoll: siehe [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md)
(Bonjour `_qr-keyboard._tcp`, Port 8080 mit Fallback auf freien Port,
JSON-Nachrichten über WebSocket). Seit v0.6.0 ist die Verbindung gekoppelt
(einmaliges OTP-Pairing) und Ende-zu-Ende verschlüsselt — siehe
[`../SECURITY.md`](../SECURITY.md).

## Voraussetzungen

- macOS 13 (Ventura) oder neuer
- Xcode bzw. Swift-Toolchain (Swift 5.9+)

## Bauen

```sh
cd macos
make app
```

Das erzeugt das App-Bundle **`dist/QR Keyboard Host.app`** (Release-Build,
ad-hoc-signiert). Das Bundle ist wichtig, damit macOS die
Bedienungshilfen-Berechtigung sauber **pro App** zuordnen kann.

Weitere Targets:

| Target       | Wirkung                                   |
| ------------ | ----------------------------------------- |
| `make build` | nur das Release-Binary bauen              |
| `make app`   | App-Bundle unter `dist/` erzeugen         |
| `make run`   | Bundle bauen und starten                  |
| `make clean` | Build-Artefakte und `dist/` entfernen     |

## Starten

```sh
make run
# oder:
open "dist/QR Keyboard Host.app"
```

Die App erscheint als QR-Symbol in der Menüleiste (kein Dock-Icon). Das Menü
zeigt:

- **Kopplungs-/Verbindungsstatus** („Kein Gerät gekoppelt" / „N gekoppelt · M verbunden")
- **Port und Bonjour-Dienstname** (der Hostname des Macs)
- **Bedienungshilfen-Status** (✓/✗) mit Direktlink in die Systemeinstellungen
- **„Gerät koppeln…"** — öffnet ein Fenster mit einem 6-stelligen, 90 s
  gültigen Code fürs Pairing eines neuen iPhones (siehe
  [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md))
- **Gekoppelte Geräte** — pro Gerät ein Untermenü mit Kopplungsdatum und
  „Entfernen" (löscht den gemeinsamen Schlüssel und trennt laufende Sitzungen)
- **Beenden**

Optional kann die App zu **Anmeldeobjekte** hinzugefügt werden
(Systemeinstellungen → Allgemein → Anmeldeobjekte), damit sie automatisch
startet.

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
3. Falls **„QR Keyboard Host"** bereits in der Liste steht: den **Schalter
   aktivieren**.
4. Falls die App noch nicht in der Liste steht: unten auf **„+"** klicken,
   zum Ordner `macos/dist/` navigieren und **„QR Keyboard Host.app"**
   auswählen, dann den Schalter aktivieren.
5. Ggf. mit dem Administrator-Passwort bestätigen.
6. Die App **neu starten** (Menüleiste → Beenden, dann erneut öffnen), damit
   die Berechtigung sicher greift. Im Menü sollte nun
   **„Bedienungshilfen: ✓ erteilt"** stehen.

> **Hinweis nach Updates:** Wird die App neu gebaut (neue Binary/Signatur),
> kann macOS die Berechtigung verwerfen. In dem Fall den Eintrag in
> **Datenschutz & Sicherheit → Bedienungshilfen** entfernen (Minus-Taste)
> und die App wie oben beschrieben **neu hinzufügen** bzw. den Schalter
> erneut aktivieren.

## Lokales Netzwerk

Ab macOS 15 (Sequoia) kann macOS zusätzlich eine Freigabe für das **lokale
Netzwerk** abfragen — diese ebenfalls erlauben, sonst findet das iPhone den
Mac nicht per Bonjour.

## Funktionsweise (Kurzfassung)

- WebSocket-Server via `Network.framework` (`NWListener` + WebSocket-Options,
  `autoReplyPing`), fester Port **8080**, bei Belegung automatisch ein freier
  Port (der iOS-Client nutzt immer den via Bonjour aufgelösten Port).
- Bonjour-Advertising als `_qr-keyboard._tcp` mit TXT-Record `v=2`.
- Jede Verbindung durchläuft entweder das OTP-Pairing (nur bei geöffnetem
  „Gerät koppeln…"-Fenster) oder den Sitzungs-Handshake für bereits
  gekoppelte Geräte; danach ausschließlich ChaChaPoly-verschlüsselte Frames
  (Curve25519 + HKDF-SHA256, Identität + PSKs in der Keychain). Details:
  [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md).
- Mehrere iPhones können gleichzeitig verbunden sein; Scans werden strikt
  sequenziell getippt (Reihenfolge: Text → Tab → Enter).
- Text-Injektion erfolgt Unicode-basiert über `CGEvent` und ist damit
  unabhängig vom aktiven Tastaturlayout (auch Emoji und Sonderzeichen).
