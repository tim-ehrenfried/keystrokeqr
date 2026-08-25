# QR-Keyboard

**Scanne einen QR-/Barcode mit dem iPhone — der Text wird sofort an der Cursor-Position auf deinem Mac eingetippt.**

Ein zweiteiliges Open-Source-System, das komplett **lokal im WLAN** funktioniert — keine Cloud, keine Accounts, Peer-to-Peer.

```
┌─────────────┐   Bonjour/mDNS Discovery    ┌──────────────────┐
│   iPhone    │ ──────────────────────────▶ │       Mac        │
│  Scanner-   │                             │  Menüleisten-App │
│    App      │   WebSocket (lokales WLAN)  │                  │
│ (SwiftUI +  │ ──────────────────────────▶ │  CGEvent-Key-    │
│AVFoundation)│      {"type":"scan",…}      │  Injection ⌨️     │
└─────────────┘                             └──────────────────┘
```

## Komponenten

| Komponente | Pfad | Technologie |
|---|---|---|
| **macOS-Host** (Menüleisten-App) | [`macos/`](macos/) | Swift, Network.framework, CGEvent |
| **iOS-Scanner** (Client) | [`ios/`](ios/) | SwiftUI, AVFoundation, Network.framework |
| **Protokoll-Spezifikation** | [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | Bonjour `_qr-keyboard._tcp` + WebSocket/JSON |

## So funktioniert es

1. Die **Mac-App** startet einen lokalen WebSocket-Server (Port 8080, automatischer Fallback) und macht ihn per **Bonjour** (`_qr-keyboard._tcp`) im WLAN auffindbar.
2. Die **iPhone-App** findet den Mac automatisch — ohne IP-Eingabe — und verbindet sich.
3. Jeder erkannte QR-/Barcode wird mit haptischem Feedback sofort an den Mac gesendet (1 s Scan-Cooldown gegen Doppel-Scans).
4. Der Mac tippt den Text als **echte Tastaturanschläge** (CGEvent, Unicode-sicher, layout-unabhängig) in das aktuell fokussierte Fenster — optional gefolgt von **Tab** und/oder **Enter** (in der iPhone-App umschaltbar).

## Schnellstart

### Mac (zuerst)

```bash
cd macos
make app        # baut „QR Keyboard Host.app"
open build/"QR Keyboard Host.app"
```

⚠️ **Einmalig nötig:** Bedienungshilfen-Berechtigung erteilen, sonst kann die App nicht tippen:
**Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → „QR Keyboard Host" aktivieren.**
Details: [macos/README.md](macos/README.md)

### iPhone

```bash
cd ios
open QRKeyboardScanner.xcodeproj
```

In Xcode ein Signing-Team wählen und auf dem iPhone installieren. Beim ersten Start Kamera- und Lokales-Netzwerk-Berechtigung erlauben. Details: [ios/README.md](ios/README.md)

## Sicherheit & Datenschutz

- **Kein Cloud-Dienst**: Die Daten verlassen dein WLAN nicht.
- Verbindung nur im lokalen Netz; der Mac-Server lauscht ohne Authentifizierung — betreibe ihn nur in vertrauenswürdigen Netzen (Heim-/Firmen-WLAN).
- Bricht die Verbindung ab, sucht die iPhone-App automatisch neu (Bonjour-Re-Browse mit Backoff).

## Versionierung

SemVer, siehe [CHANGELOG.md](CHANGELOG.md). Aktuelle Version: **0.1.0**.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
