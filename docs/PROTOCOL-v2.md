# KeystrokeQR – Netzwerkprotokoll v2 (Pairing + Verschlüsselung)

Verbindliche Spezifikation für die verschlüsselte, gekoppelte Variante. Löst v1 ab
(harter Schnitt, siehe [PROTOCOL.md](PROTOCOL.md) für v1). Ziel: nur explizit
gekoppelte iPhones können senden, aller Verkehr ist verschlüsselt und beidseitig
authentifiziert, Host-Spoofing läuft ins Leere.

**Implementiert seit v0.6.0** — macOS-Host (`macos/Sources/QRKeyboardHost/CryptoManager.swift`,
`PairingCoordinator.swift`, `PairingWindowController.swift`, `ScanServer.swift`)
und iOS-Client (`ios/QRKeyboardScanner/CryptoManager.swift`, `ConnectionManager.swift`,
`PairingView.swift`, `PairedMacsView.swift`). Beide Implementierungen stammen
aus demselben Repo und wurden konsistent gehalten (identische Salt-/Info-Strings,
identisches Nonce-Schema — siehe unten).

## Krypto-Baukasten (CryptoKit)

- **Schlüsselaustausch:** Curve25519 Key Agreement (`Curve25519.KeyAgreement`).
- **KDF:** HKDF-SHA256.
- **AEAD:** ChaChaPoly (`ChaChaPoly.seal/open`) für alle Nutz-Frames.
- **MAC (Pairing-Bestätigung):** HMAC-SHA256.
- **OTP:** 6 Ziffern, kryptografisch zufällig (`SystemRandomNumberGenerator`), 90 s gültig.
- Alle Binärwerte in JSON sind **Base64** (Standard-Alphabet).

## Discovery

- Service-Typ `_keystrokeqr._tcp`, Port wie v1 (Bonjour-aufgelöst).
- **TXT-Record:** `v=2`. Ein Client, der nur `v=1` sieht, meldet „Bitte Mac-App aktualisieren".
  Ein v2-Host akzeptiert ausschließlich v2-Clients.

## Transport

- WebSocket über `Network.framework` wie v1 (Text-Frames, UTF-8-JSON), **plus** eine
  Anwendungs-Verschlüsselungsschicht (unten). Kein NWProtocolTLS nötig — die AEAD-Schicht
  liefert Vertraulichkeit + Authentizität. (Bewusste Entscheidung: application-layer AEAD
  mit CryptoKit ist robuster umzusetzen als NWProtocolTLS-PSK und an das Pairing gebunden.)

---

## Persistenter Zustand

**Mac (Keychain, Service `de.timehrenfried.keystrokeqr.host`):**
- Eigenes langlebiges Identitäts-Keypair (Curve25519), einmalig erzeugt.
- Pro gekoppeltem Gerät: `deviceID` (UUID), Anzeigename, dessen Public Key, abgeleitetes
  **PSK** (32 Byte), Pairing-Datum.

**iOS (Keychain):**
- Eigenes langlebiges Identitäts-Keypair.
- Pro gekoppeltem Mac: Mac-Name, Mac-Public-Key, `deviceID` (die der Mac uns gab), **PSK**.

Das PSK ist der langlebige gemeinsame Geheimschlüssel; er wird beim Pairing einmalig
etabliert und danach nie über das Netz übertragen.

---

## Phase 1 – Pairing (einmalig)

Ausgelöst am **Mac**: Menü „Gerät koppeln…" → Popover generiert OTP (6 Ziffern, 90 s),
öffnet ein **Pairing-Fenster**. Nur während dieses Fensters akzeptiert der Host
`pair_hello`. Pro OTP genau **ein** erfolgreicher Versuch; bei falschem MAC wird das
OTP sofort verworfen (kein Brute-Force über mehrere Versuche).

iOS zeigt Setup-Screen: Mac aus Bonjour-Liste wählen, OTP eintippen, verbinden.

Nachrichten (Klartext-JSON, nur im Pairing-Fenster gültig):

### 1. Client → Host `pair_hello`
```json
{ "type": "pair_hello", "clientPub": "<base64 X25519 pub>", "deviceName": "Tims iPhone" }
```

### 2. Host → Client `pair_challenge`
```json
{ "type": "pair_challenge", "hostPub": "<base64 X25519 pub>" }
```

Beide Seiten berechnen jetzt:
- `shared = X25519(eigenerPriv, gegenPub)`
- `PSK = HKDF-SHA256(ikm: shared, salt: "qrkb-pair-v2", info: clientPub‖hostPub, len: 32)`
- `confirmKey = HKDF-SHA256(ikm: shared, salt: "qrkb-confirm-v2", info: clientPub‖hostPub, len: 32)`
- `expectedMAC = HMAC-SHA256(key: confirmKey, message: UTF8(OTP))`

Der OTP fließt so nur als MAC-Nachweis ein und geht nie im Klartext über die Leitung;
ein MITM, der die Public Keys austauscht, kann `expectedMAC` ohne den (nur am Bildschirm
sichtbaren) OTP nicht erzeugen.

### 3. Client → Host `pair_confirm`
```json
{ "type": "pair_confirm", "mac": "<base64 HMAC(confirmKey, OTP)>" }
```

Host prüft `mac == expectedMAC` (konstante Zeit, `HMAC.isValidAuthenticationCode`).
- **Gültig:** Host speichert Gerät (neue `deviceID`), antwortet:
  ```json
  { "type": "pair_ok", "deviceID": "<uuid>", "hostName": "Tims MacBook Pro" }
  ```
  Client speichert PSK + Mac-Infos + deviceID. Pairing-Fenster schließt. Der
  Host **schließt danach die Pairing-Verbindung** (Implementierungsdetail,
  nicht Teil der Nachricht selbst); der Client verbindet sich für Phase 2
  regulär neu (`session_hello`) — mit dem frisch gespeicherten PSK.
- **Ungültig / Fenster zu / OTP abgelaufen:**
  ```json
  { "type": "pair_error", "error": "bad_otp" }
  ```
  (weitere `error`: `pairing_closed`, `pairing_expired`) → OTP verworfen, Verbindung getrennt.

---

## Phase 2 – Gesicherte Sitzung (jede normale Verbindung)

Nach Bonjour-Connect führen **gekoppelte** Geräte einen kurzen Handshake, der aus dem PSK
einen frischen Sitzungsschlüssel ableitet (Forward Secrecy pro Sitzung über Nonces):

### 1. Client → Host `session_hello`
```json
{ "type": "session_hello", "deviceID": "<uuid>", "nonce": "<base64 16B>" }
```
Kennt der Host die `deviceID` nicht → `{ "type": "session_error", "error": "not_paired" }`,
Verbindung zu. (Client löscht dann seinen PSK-Eintrag und bietet Neu-Pairing an.)

### 2. Host → Client `session_ready`
```json
{ "type": "session_ready", "nonce": "<base64 16B>" }
```

Beide leiten ab:
- `sessionKey = HKDF-SHA256(ikm: PSK, salt: clientNonce‖hostNonce, info: "qrkb-session-v2", len: 32)`
- Ein 96-bit-Nonce-Zähler je Richtung, beginnend bei 0, monoton steigend (niemals wiederverwenden).

### 3. Verschlüsselte Frames (beide Richtungen)
```json
{ "type": "enc", "seq": 0, "ct": "<base64 ChaChaPoly ciphertext‖tag>" }
```
- **Implementierungspräzisierung (Abweichung von einer früheren Formulierung
  dieses Dokuments):** `ct` = Base64 von `ciphertext ‖ tag` (16-Byte-Tag am
  Ende) — **ohne** den 12-Byte-Nonce. CryptoKits `ChaChaPoly.SealedBox.combined`
  hängt den Nonce IMMER voran; das widerspräche dem Sinn von „nonce implizit
  via seq“ (den Nonce gerade NICHT zu übertragen, da beide Seiten ihn ohnehin
  deterministisch rekonstruieren). Host und Client dieses Repos implementieren
  beide `ciphertext‖tag` — ein Client, der stattdessen `combined` (mit Nonce)
  sendet, ist mit diesem Host NICHT kompatibel.
- `nonce` = 12 Byte = `richtungsPräfix(4B)‖bigEndian(seq)(8B)` (Client- und Host-Richtung
  haben unterschiedliche 4-Byte-Präfixe → keine Nonce-Kollision). Die
  Präfixe sind Implementierungsdetail (siehe `FrameDirection` in beiden
  `CryptoManager.swift`), müssen aber auf Host und Client exakt übereinstimmen.
- Klartext ist das jeweilige v1-JSON (`scan` bzw. `ack`), UTF-8.
- `seq` muss pro Richtung streng monoton steigen; ein Frame mit seq ≤ letztem wird verworfen
  (Replay-Schutz). AEAD-Öffnen-Fehler → Frame verwerfen, Sitzung beenden.

### Nutzlast (entschlüsselt) – unverändert gegenüber v1
- Client→Host: `{ "type":"scan", "text":…, "autoEnter":…, "autoTab":… }`
- Host→Client: `{ "type":"ack", "ok":…, "error"?:… }`
- Limits aus v1 gelten weiter (Frame ≤ 64 KiB, `text` ≤ 8192 UTF-16 → `payload_too_large`).

---

## Fehlercodes (gesamt)
`bad_otp`, `pairing_closed`, `pairing_expired`, `not_paired`, `bad_session`,
`accessibility_denied`, `invalid_message`, `payload_too_large`.
Clients ignorieren unbekannte Fehlercodes tolerant.

## Geräteverwaltung (nur am Mac)
Mac-Menü listet gekoppelte Geräte (Name + Pairing-Datum) mit „Entfernen" → PSK sofort aus
Keychain gelöscht, laufende Sitzung des Geräts wird beendet. Pairing/Entfernen ist NUR lokal
am Mac möglich, nie über das Netz auslösbar.

## Restrisiko (dokumentiert)
Der 6-stellige OTP hat ~20 bit; ein aktiver MITM im selben LAN hätte während des 90-s-Fensters
**einen** Rateversuch (1:1.000.000), danach ist das OTP verbrannt. Für ein LAN-Werkzeug
akzeptiert; wer höhere Sicherheit will, koppelt in einem vertrauenswürdigen Netz.
