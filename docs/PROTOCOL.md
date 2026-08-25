# KeystrokeQR – Network Protocol (v1)

> **Historical — superseded since v0.6.0 by [PROTOCOL-v2.md](PROTOCOL-v2.md)**
> (pairing + end-to-end encryption, hard cut: v1 hosts/clients are
> incompatible with v2 peers). This document remains as a reference for the
> (unencrypted) payload — the "Messages" section below (`scan`/`ack`) still
> applies unchanged as the plaintext **inside** the v2 `enc` frames.

Authoritative specification for both components (macOS host & iOS client).

## Discovery (Bonjour/mDNS)

- **Service type:** `_keystrokeqr._tcp`
- **Domain:** `local.`
- **Service name:** the Mac's hostname (e.g. "Tim's MacBook Pro")
- **Port:** `8080` (fixed; if the port is unavailable, the host automatically picks a free one — the client ALWAYS uses the port resolved via Bonjour, never a hardcoded 8080)
- **TXT record:** `v=1` (protocol version)

## Transport

- **WebSocket** over TCP via `Network.framework` (`NWProtocolWebSocket`).
  - Host: `NWListener` with WebSocket options (server mode, `autoReplyPing = true`).
  - Client: `NWConnection` with WebSocket options to the endpoint discovered via Bonjour.
- No TLS layer (purely local network, peer-to-peer). No cloud relay.

## Messages (JSON, text frames, UTF-8)

### Client → Host: Scan

```json
{
  "type": "scan",
  "text": "<scanned string>",
  "autoEnter": false,
  "autoTab": false
}
```

- `text`: raw payload of the QR/barcode (arbitrary Unicode).
- `autoEnter`: the host additionally sends the Return key after the text.
- `autoTab`: the host additionally sends the Tab key after the text.
- If both are set, the order is: text → Tab → Enter.

### Host → Client: Acknowledgement

```json
{ "type": "ack", "ok": true }
```

On error (e.g. missing Accessibility permission):

```json
{ "type": "ack", "ok": false, "error": "accessibility_denied" }
```

Error codes: `accessibility_denied`, `invalid_message`, `payload_too_large`.

### Limits (DoS protection, since host v0.5.0)

- **WebSocket frame:** max. **64 KiB** (larger frames are dropped by the host's transport layer).
- **`text`:** max. **8192 UTF-16 code units** — covers every real-world QR/barcode capacity.
  Exceeding it → `{ "type": "ack", "ok": false, "error": "payload_too_large" }`, nothing is typed.
- Clients must tolerantly ignore unknown error codes.

### Keepalive

WebSocket protocol-level ping/pong (autoReplyPing). No custom messages needed.

## Behavior

- The host types `text` as real keystrokes via `CGEvent` (Unicode injection, layout-independent) into the currently focused window; afterwards Tab/Enter as keycode events if requested.
- The client freezes for 1 s after a detection-triggering scan (cooldown), with haptic feedback on detection.
- Connection loss: the client restarts the Bonjour browse and reconnects automatically.
- Multiple simultaneous clients are allowed; the host processes scans sequentially.
