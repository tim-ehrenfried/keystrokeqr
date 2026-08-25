# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.
Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [SemVer](https://semver.org/lang/de/).

## [0.1.0] – 2026-08-25

### Added
- **macOS-Host** (`macos/`): Menüleisten-App mit lokalem WebSocket-Server (Network.framework, Port 8080 mit Fallback), Bonjour-Advertising `_qr-keyboard._tcp`, Key-Injection via CGEvent (Unicode-sicher, layout-unabhängig), optional Tab/Enter nach dem Text, Accessibility-Statusanzeige inkl. Direktlink in die Systemeinstellungen, Makefile-Build zum `.app`-Bundle.
- **iOS-Scanner** (`ios/`): SwiftUI-App mit Vollbild-Kamera-Sucher (AVFoundation, QR + gängige Barcode-Typen), automatischer Mac-Suche via Bonjour (keine IP-Eingabe), WebSocket-Versand, haptischem Feedback, 1-s-Scan-Cooldown, Auto-Enter-/Auto-Tab-Schaltern (persistent), automatischem Reconnect und In-App-Hilfe.
- **Protokoll-Spezifikation** `docs/PROTOCOL.md` (Bonjour + WebSocket + JSON, Ack mit Fehlercodes).
- Dokumentation: Root-README, Komponenten-READMEs mit Accessibility-Anleitung, MIT-Lizenz.
