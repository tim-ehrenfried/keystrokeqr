# KeystrokeQR – Network Protocol v2 (Pairing + Encryption)

Authoritative specification for the encrypted, paired variant. Replaces v1
(hard cut, see [PROTOCOL.md](PROTOCOL.md) for v1). Goal: only explicitly
paired iPhones can send, all traffic is encrypted and mutually
authenticated, and host spoofing leads nowhere.

**Implemented since v0.6.0** — macOS host (`macos/Sources/QRKeyboardHost/CryptoManager.swift`,
`PairingCoordinator.swift`, `PairingWindowController.swift`, `ScanServer.swift`)
and iOS client (`ios/QRKeyboardScanner/CryptoManager.swift`, `ConnectionManager.swift`,
`PairingView.swift`, `PairedMacsView.swift`). Both implementations come from
the same repo and are kept consistent (identical salt/info strings,
identical nonce scheme — see below).

## Crypto building blocks (CryptoKit)

- **Key exchange:** Curve25519 key agreement (`Curve25519.KeyAgreement`).
- **KDF:** HKDF-SHA256.
- **AEAD:** ChaChaPoly (`ChaChaPoly.seal/open`) for all payload frames.
- **MAC (pairing confirmation):** HMAC-SHA256.
- **OTP:** 6 digits, cryptographically random (`SystemRandomNumberGenerator`), valid for 90 s.
- All binary values in JSON are **Base64** (standard alphabet).

## Discovery

- Service type `_keystrokeqr._tcp`, port as in v1 (resolved via Bonjour).
- **TXT record:** `v=2`. A client that only sees `v=1` reports "Please update the Mac app".
  A v2 host accepts v2 clients exclusively.

## Transport

- WebSocket over `Network.framework` as in v1 (text frames, UTF-8 JSON), **plus** an
  application-layer encryption layer (below). No NWProtocolTLS needed — the AEAD layer
  provides confidentiality + authenticity. (Deliberate decision: application-layer AEAD
  with CryptoKit is more robust to implement than NWProtocolTLS-PSK and is tied to pairing.)

---

## Persistent state

**Mac (keychain, service `de.timehrenfried.keystrokeqr.host`):**
- Its own long-lived identity keypair (Curve25519), generated once.
- Per paired device: `deviceID` (UUID), display name, its public key, derived
  **PSK** (32 bytes), pairing date.

**iOS (keychain):**
- Its own long-lived identity keypair.
- Per paired Mac: Mac name, Mac public key, `deviceID` (the one the Mac gave us), **PSK**.

The PSK is the long-lived shared secret; it is established once during pairing
and never transmitted over the network afterwards.

---

## Phase 1 – Pairing (one-time)

Initiated on the **Mac**: menu "Pair device…" → the popover generates an OTP (6 digits, 90 s)
and opens a **pairing window**. Only while this window is open does the host accept
`pair_hello`. Exactly **one** successful attempt per OTP; on a wrong MAC the
OTP is discarded immediately (no brute force across multiple attempts).

iOS shows a setup screen: pick a Mac from the Bonjour list, type in the OTP, connect.

Messages (plaintext JSON, valid only while the pairing window is open):

### 1. Client → Host `pair_hello`
```json
{ "type": "pair_hello", "clientPub": "<base64 X25519 pub>", "deviceName": "Tim's iPhone" }
```

### 2. Host → Client `pair_challenge`
```json
{ "type": "pair_challenge", "hostPub": "<base64 X25519 pub>" }
```

Both sides now compute:
- `shared = X25519(ownPriv, peerPub)`
- `PSK = HKDF-SHA256(ikm: shared, salt: "qrkb-pair-v2", info: clientPub‖hostPub, len: 32)`
- `confirmKey = HKDF-SHA256(ikm: shared, salt: "qrkb-confirm-v2", info: clientPub‖hostPub, len: 32)`
- `expectedMAC = HMAC-SHA256(key: confirmKey, message: UTF8(OTP))`

The OTP thus only enters as a MAC proof and never crosses the wire in plaintext;
a MITM who swaps the public keys cannot produce `expectedMAC` without the OTP
(visible only on the screen).

### 3. Client → Host `pair_confirm`
```json
{ "type": "pair_confirm", "mac": "<base64 HMAC(confirmKey, OTP)>" }
```

The host checks `mac == expectedMAC` (constant time, `HMAC.isValidAuthenticationCode`).
- **Valid:** the host stores the device (new `deviceID`) and replies:
  ```json
  { "type": "pair_ok", "deviceID": "<uuid>", "hostName": "Tim's MacBook Pro" }
  ```
  The client stores the PSK + Mac info + deviceID. The pairing window closes. The
  host **then closes the pairing connection** (an implementation detail, not
  part of the message itself); the client reconnects normally for phase 2
  (`session_hello`) — using the freshly stored PSK.
- **Invalid / window closed / OTP expired:**
  ```json
  { "type": "pair_error", "error": "bad_otp" }
  ```
  (other `error` values: `pairing_closed`, `pairing_expired`) → OTP discarded, connection closed.

### Error handling & retry (mandatory, since v0.8.0)

The previous behavior (iOS runs into a timeout, the Mac shows a cryptic message and
doesn't generate a new code) is to be avoided. Instead:

- **Wrong code (`bad_otp`):**
  - **Host:** discards the old OTP, **immediately generates a new OTP automatically**,
    resets the 90 s timer, keeps the pairing window open, and shows a friendly,
    localized hint ("Wrong code – a new code was generated. Please enter it again.").
    No raw technical/crash messages in the UI.
  - **Client:** MUST react to a received `pair_error` **immediately** (not run into the
    timeout): show a clear "Wrong code" hint, clear the input field, stay on the
    pairing screen, and rebuild the pairing connection for the next attempt
    (`pair_hello`) so the handshake runs against the **new** OTP.
- **Expired code (`pairing_expired`):** As long as the pairing window is open, the host
  **automatically generates a new OTP** on expiry (no "New code" button needed) and
  resets the countdown. On `pairing_expired` the client shows a clear hint and can
  retry directly against the new code. No silent timeout without feedback.
- **Success (`pair_ok`):** The client stores the data and **closes the pairing screen
  automatically**, then connects to the session. The host briefly shows "Device paired ✓"
  and **closes the pairing window automatically** (after ~1.5 s).
- **A client timeout** is only the last resort when no response arrives at all — with a
  clear message and a "Try again", never as a substitute for the explicit errors above.

---

## Phase 2 – Secured session (every normal connection)

After the Bonjour connect, **paired** devices perform a short handshake that derives a
fresh session key from the PSK (forward secrecy per session via nonces):

### 1. Client → Host `session_hello`
```json
{ "type": "session_hello", "deviceID": "<uuid>", "nonce": "<base64 16B>" }
```
If the host doesn't know the `deviceID` → `{ "type": "session_error", "error": "not_paired" }`,
connection closed. (The client then deletes its PSK entry and offers re-pairing.)

### 2. Host → Client `session_ready`
```json
{ "type": "session_ready", "nonce": "<base64 16B>" }
```

Both derive:
- `sessionKey = HKDF-SHA256(ikm: PSK, salt: clientNonce‖hostNonce, info: "qrkb-session-v2", len: 32)`
- A 96-bit nonce counter per direction, starting at 0, monotonically increasing (never reuse).

### 3. Encrypted frames (both directions)
```json
{ "type": "enc", "seq": 0, "ct": "<base64 ChaChaPoly ciphertext‖tag>" }
```
- **Implementation clarification (deviation from an earlier wording of this
  document):** `ct` = Base64 of `ciphertext ‖ tag` (16-byte tag at the
  end) — **without** the 12-byte nonce. CryptoKit's `ChaChaPoly.SealedBox.combined`
  ALWAYS prepends the nonce; that would contradict the point of "nonce implicit
  via seq" (namely NOT transmitting the nonce, since both sides reconstruct it
  deterministically anyway). Host and client in this repo both implement
  `ciphertext‖tag` — a client that sends `combined` (with nonce) instead is
  NOT compatible with this host.
- `nonce` = 12 bytes = `directionPrefix(4B)‖bigEndian(seq)(8B)` (the client and host
  directions have different 4-byte prefixes → no nonce collision). The
  prefixes are an implementation detail (see `FrameDirection` in both
  `CryptoManager.swift` files), but must match exactly on host and client.
- The plaintext is the respective v1 JSON (`scan` or `ack`), UTF-8.
- `seq` must be strictly monotonically increasing per direction; a frame with seq ≤ the last
  one is discarded (replay protection). AEAD open failure → discard the frame, end the session.

### Payload (decrypted) – unchanged from v1
- Client→Host: `{ "type":"scan", "text":…, "autoEnter":…, "autoTab":… }`
- Host→Client: `{ "type":"ack", "ok":…, "error"?:… }`
- The v1 limits still apply (frame ≤ 64 KiB, `text` ≤ 8192 UTF-16 → `payload_too_large`).

---

## Error codes (complete)
`bad_otp`, `pairing_closed`, `pairing_expired`, `not_paired`, `bad_session`,
`accessibility_denied`, `invalid_message`, `payload_too_large`.
Clients tolerantly ignore unknown error codes.

## Device management (Mac only)
The Mac menu lists paired devices (name + pairing date) with "Remove" → the PSK is
deleted from the keychain immediately and the device's running session is terminated.
Pairing/removal is ONLY possible locally at the Mac, never triggerable over the network.

## Residual risk (documented)
The 6-digit OTP has ~20 bits; an active MITM on the same LAN would get **one** guess
during the 90 s window (1:1,000,000), after which the OTP is burned. Accepted for a
LAN tool; if you want more security, pair on a trusted network.
