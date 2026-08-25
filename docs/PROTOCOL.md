# QR-Keyboard – Netzwerkprotokoll (v1)

> **Historisch — seit v0.6.0 abgelöst durch [PROTOCOL-v2.md](PROTOCOL-v2.md)**
> (Pairing + Ende-zu-Ende-Verschlüsselung, harter Schnitt: v1-Hosts/-Clients
> sind mit v2-Gegenstellen nicht kompatibel). Dieses Dokument bleibt als
> Referenz für die (unverschlüsselte) Nutzlast erhalten — Abschnitt
> „Nachrichten“ unten (`scan`/`ack`) gilt inhaltlich unverändert als Klartext
> **innerhalb** der v2-`enc`-Frames.

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

Fehlercodes: `accessibility_denied`, `invalid_message`, `payload_too_large`.

### Limits (DoS-Schutz, ab Host v0.5.0)

- **WebSocket-Frame:** max. **64 KiB** (größere Frames verwirft die Transportschicht des Hosts).
- **`text`:** max. **8192 UTF-16-Einheiten** — deckt jede reale QR-/Barcode-Kapazität ab.
  Überschreitung → `{ "type": "ack", "ok": false, "error": "payload_too_large" }`, es wird nichts getippt.
- Clients müssen unbekannte Fehlercodes tolerant ignorieren.

### Keepalive

WebSocket-Ping/Pong der Protokollschicht (autoReplyPing). Keine eigenen Nachrichten nötig.

## Verhalten

- Host tippt `text` als echte Keystrokes via `CGEvent` (Unicode-Injection, layout-unabhängig) in das aktuell fokussierte Fenster; danach ggf. Tab/Enter als Keycode-Events.
- Client friert nach erkennungsauslösendem Scan 1 s ein (Cooldown), haptisches Feedback bei Erkennung.
- Verbindungsabriss: Client startet Bonjour-Browse neu und verbindet automatisch wieder.
- Mehrere Clients gleichzeitig sind erlaubt; der Host verarbeitet Scans sequenziell.
