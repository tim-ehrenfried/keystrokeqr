# Sicherheit (Security Policy)

KeystrokeQR ist ein bewusst einfaches, rein lokales Peer-to-Peer-System: Ein iPhone
scannt Codes, ein Mac tippt den Inhalt als Tastaturanschläge. Diese Einfachheit hat
sicherheitsrelevante Konsequenzen — dieses Dokument beschreibt sie offen.

## Threat Model

**Stand seit v0.6.0: Verbindungen sind gekoppelt (Pairing) und Ende-zu-Ende
verschlüsselt (X25519 + HKDF-SHA256 + ChaChaPoly). Nur explizit am Mac
gekoppelte iPhones können noch Keystrokes auslösen.** Details im Protokoll:
[docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).

Der macOS-Host („KeystrokeQR Host") startet einen WebSocket-Server und macht ihn
per Bonjour (`_keystrokeqr._tcp`, TXT `v=2`) im lokalen Netz auffindbar. Jede
Verbindung durchläuft entweder das Pairing (Phase 1, nur bei geöffnetem
Pairing-Fenster + korrektem OTP) oder den Sitzungs-Handshake für bereits
gekoppelte Geräte (Phase 2); danach ausschließlich AEAD-verschlüsselte Frames.

| Angriff | Status | Bewertung |
|---|---|---|
| **1. Keystroke-Injection durch beliebige LAN-Geräte** | **Geschlossen (v0.6.0)** | Ein nicht gekoppeltes Gerät kennt keine gültige `deviceID`/kein PSK → `session_hello` scheitert mit `not_paired`, keine `scan`-Nachricht wird je entschlüsselt. Nur Geräte, die den 6-stelligen OTP am physischen Mac-Bildschirm abgetippt haben, sind je gekoppelt worden. |
| **2. DoS durch übergroße Payloads** | Begrenzt (unverändert) | Der Host begrenzt WebSocket-Frames auf 64 KiB und `text` auf 8192 UTF-16-Einheiten (`payload_too_large`). Ein *gekoppeltes* Gerät kann weiterhin viele einzelne Scans hintereinander senden — Rate-Limiting existiert nicht. |
| **3. Mitlesen der Scans (Sniffing)** | **Geschlossen (v0.6.0)** | Alle Nutz-Frames sind ChaChaPoly-AEAD-verschlüsselt mit einem pro Sitzung frisch via HKDF abgeleiteten Schlüssel (Perfect-Forward-Secrecy pro Sitzung über die Nonce-Kette, nicht aber für das langlebige PSK selbst — siehe Restrisiken unten). Reiner Netzverkehrs-Mitschnitt liefert nur Chiffretext. |
| **4. Host-Spoofing** | **Geschlossen (v0.6.0)** | Ein bösartiger `_keystrokeqr._tcp`-Announcer kann zwar `session_hello` empfangen, aber ohne das clientseitige PSK keine gültige `session_ready`/`enc`-Antwort erzeugen — der Client bricht ab bzw. erkennt `not_paired` nicht vom richtigen Host. Ein Spoofer, der sich selbst als *neuer, ungekoppelter* v2- oder v1-Host ausgibt, kann zwar den Pairing-Screen bzw. die „Mac-App aktualisieren“-Meldung auslösen — ein Pairing gelingt ihm aber nur, wenn der Nutzer den am *echten* Mac-Bildschirm angezeigten OTP dort eintippt (siehe Restrisiko OTP-Entropie). |
| **5. Remote Code Execution im Host** | Nicht bekannt (unverändert) | Eingaben werden ausschließlich als JSON dekodiert (Swift `Codable`, kein `eval`, keine Shell) und als Unicode-Keystrokes ausgegeben. Es gibt keine Datei-, URL- oder Prozess-Verarbeitung von Netzwerkeingaben. |

**Nicht Teil des Threat Models:** Angreifer mit lokalem Zugriff auf den Mac oder
das iPhone (Keychain-Zugriff, physischer Zugriff während des 90-s-Pairing-Fensters)
sowie Netze, in denen sich per Definition keine unvertrauenswürdigen Geräte befinden.

## Restrisiken (dokumentiert, akzeptiert)

- **OTP-Entropie (~20 Bit).** Der 6-stellige Pairing-Code hat 1.000.000 mögliche
  Werte. Ein aktiver MITM im selben LAN während des 90-Sekunden-Pairing-Fensters
  hätte **genau einen** Rateversuch (Erfolgswahrscheinlichkeit 1:1.000.000) — das
  OTP wird beim ersten `pair_confirm`-Versuch sofort verbraucht, unabhängig vom
  Ergebnis (kein Multi-Guessing über mehrere Verbindungen). Für ein LAN-Werkzeug
  akzeptiert; wer höhere Sicherheit will, koppelt in einem Netz, in dem kein
  aktiver Angreifer mitlauschen kann (z. B. per Kabel/Hotspot statt öffentlichem WLAN).
- **PSK ist langlebig.** Der beim Pairing etablierte Pre-Shared-Key wird nie
  erneuert (nur der abgeleitete Sitzungsschlüssel ist pro Verbindung frisch).
  Wer Lese-/Schreibzugriff auf die Keychain eines der beiden Geräte erlangt
  (Malware, Backup-Extraktion, Jailbreak), kann sich dauerhaft als gekoppeltes
  Gerät ausgeben, bis der Nutzer es über „Entfernen“/„Entkoppeln“ widerruft.
- **Kein Zertifikats-Pinning der Bonjour-Identität über die Zeit.** Der Client
  korreliert gekoppelte Macs über den Bonjour-Servicenamen (Mac-Hostname), nicht
  über den öffentlichen Identitätsschlüssel. Ändert sich der Mac-Name, erkennt
  die App den Mac nicht mehr automatisch als gekoppelt (harmlos: einfach neu
  koppeln) — umgekehrt könnte ein Spoofer theoretisch denselben Namen wie ein
  bereits gekoppelter Mac annoncieren; er verfügt aber weiterhin nicht über
  dessen PSK und kann daher `session_hello` nicht erfolgreich beantworten.
- **Kein Rate-Limiting nach dem Pairing.** Ein bereits gekoppeltes, aber
  kompromittiertes Gerät kann weiterhin beliebig viele Scans hintereinander senden.

## Bewusste Design-Entscheidungen

- **Anwendungsschicht-AEAD statt TLS.** Statt `NWProtocolTLS` mit PSK-Cipher-Suites
  verschlüsselt eine dedizierte CryptoKit-Schicht (Curve25519 + HKDF-SHA256 +
  ChaChaPoly) die Nutzlast — robuster umzusetzen und direkt an das Pairing
  gebunden. Details: [docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).
- **Keine Cloud, keine Accounts.** Es gibt keinen externen Angriffsvektor über
  Server von Dritten; die Daten (inkl. PSK) verlassen niemals das lokale Netz
  bzw. die Keychain der beiden Geräte.
- **Der Host tippt, was ankommt.** Es findet bewusst **keine inhaltliche Filterung**
  der (entschlüsselten) Payload statt (auch Steuerzeichen wie Zeilenumbrüche
  werden getippt), da legitime Codes (vCards, WLAN-Konfigurationen,
  GS1-Barcodes) solche Zeichen enthalten. Die Verantwortung, **wo** der Fokus
  liegt, liegt beim Nutzer — das gilt weiterhin auch für gekoppelte Geräte.

## Empfehlungen für Nutzer

1. **Beim Pairing den OTP nicht laut vorlesen/fotografieren, wenn Unbekannte in
   Sichtweite sind** — er ist der einzige Nachweis, dass das koppelnde iPhone
   wirklich am eigenen Mac sitzt.
2. **Mac-App beenden, wenn sie nicht gebraucht wird** (Menüleiste → Beenden). Der
   Server läuft nur, solange die App läuft.
3. **Fokus bewusst setzen.** Vor dem Scannen den Cursor in das Zielfeld setzen.
   Besondere Vorsicht bei fokussiertem **Terminal**, Passwortfeldern oder
   Admin-Konsolen — dorthin getippter Text kann unmittelbar Aktionen auslösen
   (dieses Risiko bleibt auch bei gekoppelten Geräten bestehen, siehe Angriff 1
   oben — Pairing schützt vor *fremden*, nicht vor *eigenen* Fehlbedienungen).
4. **Nur eigene/bekannte Codes scannen.** Der Inhalt eines fremden QR-Codes wird
   1:1 getippt — inklusive eventueller Zeilenumbrüche.
5. **Nicht mehr benötigte Geräte entkoppeln** (Mac-Menü „Entfernen“ bzw. iPhone
   „Gekoppelte Macs verwalten“ in der Hilfe) — z. B. bei Verkauf/Verlust eines
   der beiden Geräte.

## Known Limitations

- Kein Rate-Limiting pro Client nach dem Pairing; kein Limit für die Anzahl
  gleichzeitiger Verbindungen.
- Reine v1-Hosts/-Clients (vor v0.6.0) sind mit v2-Gegenstellen nicht
  kompatibel (harter Schnitt) — die App zeigt dann „Mac-App aktualisieren“.
- Die macOS-Releases sind **ad-hoc-signiert und nicht notarisiert** (Gatekeeper-
  Hinweise siehe [docs/INSTALL.md](docs/INSTALL.md)). Wer maximale Sicherheit will,
  baut die App aus dem Quellcode selbst (`cd macos && make app`).
- Die Bedienungshilfen-Berechtigung erlaubt der App systemweite Tastatureingaben —
  das ist ihr Zweck, bedeutet aber: Wer dem Code nicht vertraut, sollte ihn vor dem
  Erteilen der Berechtigung lesen (er ist kurz).

## Sicherheitslücken melden (Responsible Disclosure)

Bitte Sicherheitsprobleme **nicht** als öffentliches GitHub-Issue melden, sondern
per E-Mail an:

**mail@tim-ehrenfried.de**

Mit einer Antwort ist in der Regel innerhalb weniger Tage zu rechnen. Bitte eine
nachvollziehbare Beschreibung (idealerweise mit Reproduktionsschritten) beilegen;
nach Behebung wird die Lücke im CHANGELOG dokumentiert und der Finder auf Wunsch
genannt.
