# QR-Keyboard – Netzwerkprotokoll (v1)

Verbindliche Spezifikation für beide Komponenten (macOS-Host & iOS-Client).

## Discovery (Bonjour/mDNS)

- **Service-Typ:** `_qr-keyboard._tcp`
- **Domain:** `local.`
- **Service-Name:** Hostname des Macs (z. B. „Tims MacBook Pro")
- **Port:** `8080` (fest; fällt der Port aus, wählt der Host automatisch einen freien Port — der Client nutzt IMMER den via Bonjour aufgelösten Port, niemals hartkodiert 8080)
- **TXT-Record:** `v=1` (Protokollversion)

## Transport

- **WebSocket** über TCP via `Network.framework` (`NWProtocolWebSocket`).
  - Host: `NWListener` mit WebSocket-Options (Server-Modus, `autoReplyPing = true`).
  - Client: `NWConnection` mit WebSocket-Options auf das via Bonjour gefundene Endpoint.
- Keine TLS-Schicht (rein lokales Netz, Peer-to-Peer). Kein Cloud-Relay.

## Nachrichten (JSON, Text-Frames, UTF-8)

### Client → Host: Scan

```json
{
  "type": "scan",
  "text": "<gescannter String>",
  "autoEnter": false,
  "autoTab": false
}
```

- `text`: Roh-Payload des QR-/Barcodes (beliebiges Unicode).
- `autoEnter`: Host sendet nach dem Text zusätzlich die Return-Taste.
- `autoTab`: Host sendet nach dem Text zusätzlich die Tab-Taste.
- Sind beide gesetzt, gilt die Reihenfolge: Text → Tab → Enter.

### Host → Client: Acknowledgement

```json
{ "type": "ack", "ok": true }
```

Bei Fehler (z. B. Accessibility-Berechtigung fehlt):

```json
{ "type": "ack", "ok": false, "error": "accessibility_denied" }
```

Fehlercodes: `accessibility_denied`, `invalid_message`.

### Keepalive

WebSocket-Ping/Pong der Protokollschicht (autoReplyPing). Keine eigenen Nachrichten nötig.

## Verhalten

- Host tippt `text` als echte Keystrokes via `CGEvent` (Unicode-Injection, layout-unabhängig) in das aktuell fokussierte Fenster; danach ggf. Tab/Enter als Keycode-Events.
- Client friert nach erkennungsauslösendem Scan 1 s ein (Cooldown), haptisches Feedback bei Erkennung.
- Verbindungsabriss: Client startet Bonjour-Browse neu und verbindet automatisch wieder.
- Mehrere Clients gleichzeitig sind erlaubt; der Host verarbeitet Scans sequenziell.
