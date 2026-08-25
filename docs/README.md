# KeystrokeQR – Dokumentation

Übersicht aller Dokumente. Scanne mit dem iPhone einen QR-/Barcode — der Text wird
sofort an der Cursor-Position auf deinem Mac eingetippt. Komplett lokal im WLAN, verschlüsselt.

← Zurück zur [Projekt-Übersicht](../README.md)

## Für Nutzer:innen

| Dokument | Worum geht's |
|---|---|
| **[INSTALL.md](INSTALL.md)** | Fertige Mac-App aus dem Release-DMG installieren (ohne Xcode), Gatekeeper-Hinweise, Bedienungshilfen freischalten. **Hier starten, wenn du KeystrokeQR nur benutzen willst.** |
| **[SETUP.md](SETUP.md)** | Kompletter Weg für Entwickler:innen: Apple-Developer-Account, iOS-App aufs iPhone, Mac-App bauen, **einmaliges Koppeln (Pairing)**, erster Test, Sperrbildschirm-Schnellstart, Troubleshooting. |

## Bedienung in Kürze

1. **Mac:** KeystrokeQR Host starten (Menüleiste) und einmalig die Bedienungshilfen-Berechtigung erteilen.
2. **iPhone:** KeystrokeQR öffnen → Mac wird automatisch gefunden.
3. **Koppeln:** Am Mac „Gerät koppeln…", den 6-stelligen Code am iPhone eingeben (nur beim ersten Mal).
4. **Scannen:** Cursor am Mac ins Zielfeld, QR-/Barcode scannen → Text wird getippt (optional + Tab/Enter).

Alles Weitere erklärt die **In-App-Hilfe** in beiden Apps.

## Technische Dokumentation

| Dokument | Worum geht's |
|---|---|
| **[PROTOCOL-v2.md](PROTOCOL-v2.md)** | Aktuelles Netzwerkprotokoll: Bonjour-Discovery, OTP-Pairing (Curve25519), verschlüsselte Sitzung (HKDF + ChaChaPoly), Fehlerbehandlung. **Verbindlich für Host & Client.** |
| **[PROTOCOL.md](PROTOCOL.md)** | Ursprüngliches, unverschlüsseltes v1-Protokoll (historisch, durch v2 abgelöst). |
| **[BRANDING.md](BRANDING.md)** | Verbindliche Namen, Bundle-IDs, Service-Typen, i18n-Grundlagen. |
| **[SECURITY.md](../SECURITY.md)** | Threat Model, Sicherheitsentscheidungen, Empfehlungen, Responsible Disclosure. |
| **[PLAN-SECURITY-DISTRIBUTION.md](PLAN-SECURITY-DISTRIBUTION.md)** | Fahrplan für App-Store/TestFlight, notarisiertes DMG und weitere Verteilung. |

## Repository-Struktur

- [`ios/`](../ios/) — iOS-Scanner-App (SwiftUI, AVFoundation), siehe [ios/README.md](../ios/README.md)
- [`macos/`](../macos/) — macOS-Menüleisten-Host (Swift, CGEvent), siehe [macos/README.md](../macos/README.md)
- [`docs/`](.) — diese Dokumentation
- [`CHANGELOG.md`](../CHANGELOG.md) — Versionshistorie (SemVer)
