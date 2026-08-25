# Plan: Verschlüsselung + Geräte-Pairing (OTP) und Distribution (Store + DMG)

Status: **Geplant, nicht umgesetzt** (Stand 2026-08-25, nach v0.5.x).
Beide Vorhaben schließen die offenen Punkte aus [SECURITY.md](../SECURITY.md) bzw. machen die Installation Xcode-frei.

---

## Teil A — Security: TLS-Verschlüsselung + einmaliges Pairing mit OTP

**Ziel:** Keine offenen Sicherheitsfragen mehr. Nur explizit gekoppelte iPhones dürfen senden (Authentizität), alles ist verschlüsselt (Vertraulichkeit), Host-Spoofing läuft ins Leere (der Client authentifiziert auch den Mac).

### Konzept

1. **Pairing (einmalig, OTP vom Mac):**
   - Mac-Menü: neuer Punkt **„Gerät koppeln…"** → zeigt 6-stelligen Einmalcode (OTP, 60 s gültig) in einem Popover.
   - iOS: Setup-Screen beim ersten Start (und unter „Neues Gerät koppeln"): Mac aus Bonjour-Liste wählen → OTP eintippen.
   - Technisch: Der OTP authentifiziert einen einmaligen Schlüsselaustausch (ECDH mit Curve25519 via CryptoKit; der OTP fließt als HMAC in die Bestätigung ein → Man-in-the-Middle beim Pairing ausgeschlossen). Ergebnis: ein langlebiges, gerätespezifisches **32-Byte-PSK (Pre-Shared Key)**.
   - Speicherung: Mac-Keychain (Liste gekoppelter Geräte: Name, Public-Key-Hash, PSK), iOS-Keychain (pro Mac ein PSK).
2. **Laufende Verbindungen: TLS-PSK**
   - `Network.framework` beidseitig mit `NWProtocolTLS` + `sec_protocol_options_add_pre_shared_key` (TLS 1.2 PSK-Cipher; kein Zertifikats-Theater nötig, PSK authentifiziert beide Seiten gleichzeitig).
   - Nicht gekoppelte Clients: TLS-Handshake schlägt fehl → können weder senden noch mitlesen. Damit sind Finding 1 (LAN-Injection), 3 (Sniffing) und 4 (Host-Spoofing) aus SECURITY.md geschlossen.
3. **Geräteverwaltung (Mac-Menü):** Liste gekoppelter iPhones mit „Entfernen" (widerruft PSK sofort). Admin-Grundregel: Pairing-UI nur am Mac, nie remote auslösbar.
4. **Protokoll v2:** TXT-Record `v=2`; Pairing-Nachrichten (`pair_request`/`pair_confirm`) laufen über einen separaten, unverschlüsselten, streng limitierten Endpunkt NUR solange das Pairing-Popover offen ist. Harter Schnitt statt Abwärtskompatibilität (beide Apps kommen aus einem Repo; alte Clients zeigen „Bitte App aktualisieren und koppeln").

### Arbeitspakete & Aufwand

| # | Paket | Aufwand |
|---|---|---|
| A1 | PROTOCOL.md v2 (Pairing-Flow, TLS-PSK, Fehlercodes `not_paired`, `pairing_expired`) | klein |
| A2 | Mac: Pairing-UI (Popover + OTP-Generator), Keychain-Store, Geräteliste im Menü | mittel |
| A3 | Mac: Listener auf TLS-PSK umstellen (PSK-Lookup per Client-Hint) | mittel |
| A4 | iOS: Setup-/Pairing-Screen, Keychain, Connection auf TLS-PSK | mittel |
| A5 | SECURITY.md aktualisieren (Findings 1/3/4 → geschlossen), Doku/Hilfe | klein |

Risiko: TLS-PSK-API von Network.framework ist schlecht dokumentiert (DispatchData-Handling) — ggf. 1 Iteration mehr einplanen. Gesamt: ~1 fokussierter Entwicklungstag mit Agents, gut in 2 Releases teilbar (erst Pairing+PSK, dann Feinschliff).

---

## Teil B — Distribution & CI/CD: App Store + notarisiertes DMG

**Ziel-Nutzererlebnis:** iOS-App aus dem **App Store** laden → Mac-Server als **DMG** von GitHub laden (notarisiert, kein Gatekeeper-Gefrickel) → koppeln → fertig. Kein Xcode für Endnutzer.

### B1 — macOS: signiertes + notarisiertes DMG (unabhängig vom Store, zuerst umsetzen)

1. **Voraussetzungen (einmalig, manuell):** Im Dev-Account ein **Developer ID Application**-Zertifikat erzeugen; App Store Connect **API-Key** (.p8, Key-ID, Issuer-ID) für die Notarisierung anlegen.
2. **GitHub-Secrets:** Zertifikat als base64-.p12 + Passwort, ASC-API-Key (3 Secrets).
3. **Release-Workflow erweitern:** `make app SIGN_IDENTITY="Developer ID Application: …"` → DMG bauen (`create-dmg` oder `hdiutil`, mit /Applications-Symlink und Hintergrundbild) → `xcrun notarytool submit --wait` → `xcrun stapler staple` → DMG als Release-Asset (ersetzt das Zip).
4. **Effekt:** Download öffnet ohne Warnung; Accessibility-Berechtigung bleibt dank stabiler Signatur dauerhaft. INSTALL.md schrumpft auf „laden, ziehen, Berechtigung erteilen".
5. Optional später: **Sparkle** für Auto-Updates aus den GitHub-Releases.

### B2 — iOS: TestFlight → App Store

1. **Einmalig in App Store Connect:** Bundle-IDs registrieren (App + Widget-Extension), App-Eintrag anlegen, Datenschutz-Angaben („Privacy Nutrition Label": keine Datenerhebung), Screenshots (iPhone 6,7"/6,1"), Beschreibung; Review-Notiz, dass die App ein lokales Mac-Gegenstück braucht (Link + Testvideo beilegen — wichtig, sonst Ablehnungsrisiko „App wirkt funktionslos").
2. **CI:** GitHub Actions mit **Fastlane** (`build_app` + `upload_to_testflight` / `deliver`), Signing via ASC-API-Key (cloud-managed certificates, kein match-Repo nötig). Trigger: Tag `v*` → TestFlight-Build; manueller Workflow-Dispatch → „Zur Review einreichen".
3. **Versionierung:** MARKETING_VERSION aus Git-Tag ableiten, Build-Nummer = GitHub-Run-Number.
4. **Phasen:** (1) TestFlight intern (sofort nutzbar, auch für Kollegen), (2) App-Store-Review. Realistisch 1–3 Review-Runden; das Pairing aus Teil A sollte VORHER drin sein (Reviewer im fremden Netz + unauthentifizierter Keystroke-Server wäre auch inhaltlich heikel).

### Reihenfolge-Empfehlung

1. **A (Security/Pairing)** — schließt die Sicherheitslücken und ist Voraussetzung für einen sauberen Store-Auftritt.
2. **B1 (DMG notarisiert)** — kleiner, sofortiger Gewinn für die Verteilung des Servers.
3. **B2 (TestFlight → App Store)** — der längste Teil wegen Review/Metadaten.
