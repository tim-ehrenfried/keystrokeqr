# Security Policy

KeystrokeQR is a deliberately simple, purely local peer-to-peer system: an iPhone
scans codes, a Mac types their contents as keystrokes. That simplicity has
security-relevant consequences — this document describes them openly.

## Threat Model

**As of v0.6.0: connections are paired and end-to-end encrypted
(X25519 + HKDF-SHA256 + ChaChaPoly). Only iPhones explicitly paired at the Mac
can trigger keystrokes.** Details in the protocol spec:
[docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).

The macOS host ("KeystrokeQR Host") starts a WebSocket server and advertises it
on the local network via Bonjour (`_keystrokeqr._tcp`, TXT `v=2`). Every
connection goes through either pairing (phase 1, only while the pairing window
is open and with the correct OTP) or the session handshake for already-paired
devices (phase 2); after that, exclusively AEAD-encrypted frames.

| Attack | Status | Assessment |
|---|---|---|
| **1. Keystroke injection by arbitrary LAN devices** | **Closed (v0.6.0)** | An unpaired device has no valid `deviceID`/PSK → `session_hello` fails with `not_paired`, and no `scan` message is ever decrypted. Only devices that typed in the 6-digit OTP shown on the physical Mac screen have ever been paired. |
| **2. DoS via oversized payloads** | Limited (unchanged) | The host caps WebSocket frames at 64 KiB and `text` at 8192 UTF-16 code units (`payload_too_large`). A *paired* device can still send many individual scans in rapid succession — there is no rate limiting. |
| **3. Eavesdropping on scans (sniffing)** | **Closed (v0.6.0)** | All payload frames are ChaChaPoly-AEAD-encrypted with a key freshly derived via HKDF per session (perfect forward secrecy per session through the nonce chain, but not for the long-lived PSK itself — see residual risks below). A raw network capture yields only ciphertext. |
| **4. Host spoofing** | **Closed (v0.6.0)** | A malicious `_keystrokeqr._tcp` announcer can receive `session_hello`, but without the client-side PSK it cannot produce a valid `session_ready`/`enc` response — the client aborts, and a `not_paired` from the wrong host is not accepted as coming from the real one. A spoofer posing as a *new, unpaired* v2 or v1 host can trigger the pairing screen or the "Please update the Mac app" message — but a pairing only succeeds if the user types in the OTP shown on the *real* Mac's screen (see the OTP-entropy residual risk). |
| **5. Remote code execution in the host** | Not known (unchanged) | Input is decoded exclusively as JSON (Swift `Codable`, no `eval`, no shell) and emitted as Unicode keystrokes. There is no file, URL, or process handling of network input. |

**Not part of the threat model:** attackers with local access to the Mac or the
iPhone (keychain access, physical access during the 90-second pairing window),
and networks that by definition contain no untrusted devices.

## Residual risks (documented, accepted)

- **OTP entropy (~20 bits).** The 6-digit pairing code has 1,000,000 possible
  values. An active MITM on the same LAN during the 90-second pairing window
  would get **exactly one** guess (success probability 1:1,000,000) — the OTP
  is consumed immediately on the first `pair_confirm` attempt, regardless of the
  outcome (no multi-guessing across multiple connections). Accepted for a LAN
  tool; if you want more security, pair on a network where no active attacker
  can listen in (e.g. wired or personal hotspot instead of public Wi-Fi).
- **The PSK is long-lived.** The pre-shared key established during pairing is
  never rotated (only the derived session key is fresh per connection).
  Anyone who gains read/write access to the keychain of either device
  (malware, backup extraction, jailbreak) can permanently impersonate a paired
  device until the user revokes it via "Remove"/unpairing.
- **No pinning of the Bonjour identity over time.** The client correlates
  paired Macs by their Bonjour service name (the Mac's hostname), not by their
  public identity key. If the Mac's name changes, the app no longer recognizes
  it as paired automatically (harmless: just pair again) — conversely, a
  spoofer could in theory announce the same name as an already-paired Mac, but
  it still doesn't have that Mac's PSK and therefore cannot answer
  `session_hello` successfully.
- **No rate limiting after pairing.** An already-paired but compromised device
  can still send arbitrarily many scans in a row.

## Deliberate design decisions

- **Application-layer AEAD instead of TLS.** Rather than `NWProtocolTLS` with
  PSK cipher suites, a dedicated CryptoKit layer (Curve25519 + HKDF-SHA256 +
  ChaChaPoly) encrypts the payload — more robust to implement and directly tied
  to pairing. Details: [docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).
- **No cloud, no accounts.** There is no external attack vector via third-party
  servers; the data (including the PSK) never leaves the local network or the
  keychains of the two devices.
- **The host types whatever arrives.** The (decrypted) payload is deliberately
  **not filtered by content** (control characters such as line breaks are typed
  too), because legitimate codes (vCards, Wi-Fi configurations, GS1 barcodes)
  contain such characters. The responsibility for **where** the focus is lies
  with the user — this still applies to paired devices as well.

## Recommendations for users

1. **Don't read the OTP out loud or photograph it during pairing when strangers
   are in view** — it is the only proof that the pairing iPhone is really
   sitting at your own Mac.
2. **Quit the Mac app when you're not using it** (menu bar → Quit). The
   server only runs while the app is running.
3. **Set the focus deliberately.** Place the cursor in the target field before
   scanning. Be especially careful with a focused **terminal**, password fields,
   or admin consoles — text typed there can trigger actions immediately
   (this risk remains even with paired devices, see attack 1 above — pairing
   protects against *strangers*, not against your *own* mistakes).
4. **Only scan your own/known codes.** The contents of a third-party QR code are
   typed verbatim — including any line breaks.
5. **Unpair devices you no longer need** (Mac menu "Remove" or iPhone
   "Manage paired Macs" in the help section) — e.g. when selling or losing
   either device.

## Known Limitations

- No per-client rate limiting after pairing; no limit on the number of
  simultaneous connections.
- Pure v1 hosts/clients (before v0.6.0) are incompatible with v2 peers
  (hard cut) — the app then shows "Please update the Mac app".
- The macOS releases are **ad-hoc signed and not notarized** (Gatekeeper
  notes in [docs/INSTALL.md](docs/INSTALL.md)). If you want maximum security,
  build the app from source yourself (`cd macos && make app`).
- The Accessibility permission allows the app to type system-wide keystrokes —
  that is its purpose, but it means: if you don't trust the code, read it before
  granting the permission (it's short).

## Reporting vulnerabilities (responsible disclosure)

Please do **not** report security issues as public GitHub issues; instead, email:

**mail@tim-ehrenfried.de**

You can usually expect a reply within a few days. Please include a
comprehensible description (ideally with reproduction steps); after a fix, the
issue will be documented in the CHANGELOG and the reporter credited on request.
