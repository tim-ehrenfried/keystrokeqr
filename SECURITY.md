# Sicherheit (Security Policy)

QR-Keyboard ist ein bewusst einfaches, rein lokales Peer-to-Peer-System: Ein iPhone
scannt Codes, ein Mac tippt den Inhalt als Tastaturanschläge. Diese Einfachheit hat
sicherheitsrelevante Konsequenzen — dieses Dokument beschreibt sie offen.

## Threat Model

**Kernaussage: Jedes Gerät im selben Netzwerk kann Keystrokes auf dem Mac auslösen.
Das ist eine bewusste Design-Entscheidung, kein Versehen.**

Der macOS-Host („QR Keyboard Host") startet einen WebSocket-Server ohne TLS und ohne
Authentifizierung und macht ihn per Bonjour (`_qr-keyboard._tcp`) im lokalen Netz
auffindbar. Daraus folgt:

| Angriff | Möglich? | Bewertung |
|---|---|---|
| **Keystroke-Injection durch beliebige LAN-Geräte**: Jeder Netzwerkteilnehmer kann sich verbinden und eine `scan`-Nachricht senden; der Mac tippt den Text in das gerade fokussierte Fenster. | Ja (by design) | Das zentrale Risiko. Ist z. B. gerade ein **Terminal** fokussiert und die Payload enthält Zeilenumbrüche (oder der Angreifer setzt `autoEnter`), werden **Befehle ausgeführt**. Gleiches gilt für Adresszeilen, Chat-Fenster, Formulare. |
| **Mitlesen der Scans (Sniffing)**: Verkehr läuft unverschlüsselt über das WLAN. | Ja | Wer den lokalen Netzverkehr mitschneiden kann, sieht alle gescannten Inhalte im Klartext. Keine sensiblen Daten (Passwörter, Tokens) über dieses System tippen, wenn das Netz nicht vertrauenswürdig ist. |
| **Host-Spoofing**: Ein bösartiges Gerät annonciert selbst `_qr-keyboard._tcp`; die iPhone-App verbindet sich (bei genau einem gefundenen Dienst automatisch) und sendet Scans dorthin. | Ja | Gescannte Inhalte können an einen Angreifer statt an den eigenen Mac gehen. Bei mehreren gefundenen Diensten zeigt die App eine Auswahl — den Namen prüfen. |
| **DoS durch übergroße Payloads** („Mac minutenlang volltippen") | Begrenzt | Seit v0.5.0 begrenzt der Host WebSocket-Frames auf 64 KiB und `text` auf 8192 UTF-16-Einheiten (Ablehnung mit `payload_too_large`). Ein Angreifer kann dennoch viele einzelne Scans hintereinander senden. |
| **Remote Code Execution im Host** | Nicht bekannt | Eingaben werden ausschließlich als JSON dekodiert (Swift `Codable`, kein `eval`, keine Shell) und als Unicode-Keystrokes ausgegeben. Es gibt keine Datei-, URL- oder Prozess-Verarbeitung von Netzwerkeingaben. |

**Nicht Teil des Threat Models:** Angreifer mit lokalem Zugriff auf den Mac (die
brauchen dieses Tool nicht) sowie Netze, in denen sich per Definition keine
unvertrauenswürdigen Geräte befinden.

## Bewusste Design-Entscheidungen

- **Kein TLS, keine Authentifizierung, kein Pairing.** Das System ist für
  vertrauenswürdige private Netze (Heim-/abgeschottetes Firmen-WLAN) gebaut.
  Zero-Config-Komfort (App öffnen → verbunden) wurde bewusst über
  Verbindungssicherheit gestellt. Ein Pairing-/PSK-Mechanismus wäre eine mögliche
  künftige Erweiterung, ist aber aktuell nicht implementiert.
- **Keine Cloud, keine Accounts.** Es gibt keinen externen Angriffsvektor über
  Server von Dritten; die Daten verlassen das lokale Netz nicht.
- **Der Host tippt, was ankommt.** Es findet bewusst **keine inhaltliche Filterung**
  der Payload statt (auch Steuerzeichen wie Zeilenumbrüche werden getippt), da
  legitime Codes (vCards, WLAN-Konfigurationen, GS1-Barcodes) solche Zeichen
  enthalten. Die Verantwortung, **wo** der Fokus liegt, liegt beim Nutzer.

## Empfehlungen für Nutzer

1. **Nur in vertrauenswürdigen Netzen betreiben.** Niemals in fremden/öffentlichen
   WLANs (Hotel, Café, Messe) laufen lassen — dort kann jeder Gast Tastatureingaben
   auf deinem Mac auslösen und deine Scans mitlesen.
2. **Mac-App beenden, wenn sie nicht gebraucht wird** (Menüleiste → Beenden). Der
   Server läuft nur, solange die App läuft. Die App nicht dauerhaft als
   Anmeldeobjekt betreiben, wenn der Mac regelmäßig in fremden Netzen hängt.
3. **Fokus bewusst setzen.** Vor dem Scannen den Cursor in das Zielfeld setzen.
   Besondere Vorsicht bei fokussiertem **Terminal**, Passwortfeldern oder
   Admin-Konsolen — dorthin getippter Text kann unmittelbar Aktionen auslösen.
4. **Nur eigene/bekannte Codes scannen.** Der Inhalt eines fremden QR-Codes wird
   1:1 getippt — inklusive eventueller Zeilenumbrüche.
5. **Bei der Dienst-Auswahl auf dem iPhone den Mac-Namen prüfen**, wenn mehrere
   Hosts angezeigt werden.
6. **Gastnetz/VLAN nutzen**, wenn im Netz nicht vertrauenswürdige Geräte (IoT,
   Gäste) hängen.

## Known Limitations

- Keine Verschlüsselung, keine Authentifizierung, kein Pairing (siehe oben).
- Der Host unterscheidet Clients nicht; Rate-Limiting pro Client und ein Limit für
  die Anzahl gleichzeitiger Verbindungen existieren nicht.
- Die iPhone-App verbindet sich bei genau einem gefundenen Bonjour-Dienst
  automatisch, ohne den Host kryptografisch zu verifizieren.
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
