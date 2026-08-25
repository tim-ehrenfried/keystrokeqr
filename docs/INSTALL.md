# Installation für Endnutzer (ohne Xcode)

Diese Anleitung richtet sich an Nutzer, die die fertige macOS-App einfach nur
**herunterladen und verwenden** möchten. Wer selbst bauen will (oder die iOS-App
aufs iPhone bringen möchte), findet alles in [SETUP.md](SETUP.md).

## 1. macOS-App herunterladen

1. Neueste Version laden:
   **[github.com/tim-ehrenfried/qr-keyboard/releases/latest](https://github.com/tim-ehrenfried/qr-keyboard/releases/latest)**
   → unter *Assets* die Datei **`QR-Keyboard-Host-macOS.zip`** anklicken.
2. Das Zip im Downloads-Ordner doppelklicken (falls macOS es nicht schon
   automatisch entpackt hat) → es erscheint **„QR Keyboard Host.app"**.
3. Die App in den Ordner **Programme** ziehen (Finder → Gehe zu → Programme).

Voraussetzung: **macOS 13 (Ventura) oder neuer**.

## 2. Gatekeeper: „App kann nicht geöffnet werden"

Die App ist **ad-hoc-signiert und nicht notarisiert** (Open-Source-Projekt ohne
bezahltes Apple-Developer-Zertifikat). Beim ersten Start blockiert macOS sie
deshalb mit einer Warnung. Zwei Wege, das einmalig freizugeben:

**Weg A — Rechtsklick:**

1. Im Ordner *Programme* mit **Rechtsklick** (bzw. ctrl-Klick) auf
   „QR Keyboard Host" → **Öffnen**.
2. Im Dialog erneut **Öffnen** bestätigen.
   (Ab macOS 15 Sequoia ggf. zusätzlich: *Systemeinstellungen → Datenschutz &
   Sicherheit* → ganz unten bei der blockierten App **„Dennoch öffnen"**.)

**Weg B — Terminal (Quarantäne-Attribut entfernen):**

```bash
xattr -d com.apple.quarantine "/Applications/QR Keyboard Host.app"
```

Danach startet die App normal per Doppelklick.

> Wer der heruntergeladenen Binary nicht vertrauen möchte, kann die App in wenigen
> Minuten selbst aus dem Quellcode bauen: `cd macos && make app`
> (siehe [../macos/README.md](../macos/README.md)).

## 3. Bedienungshilfen freischalten (zwingend)

Damit die App den gescannten Text **tippen** darf, braucht sie die
macOS-Berechtigung **Bedienungshilfen**:

1. App starten → in der Menüleiste erscheint ein QR-Symbol.
2. *Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen* →
   Schalter bei **„QR Keyboard Host"** aktivieren.
   (Fehlt der Eintrag: unten **+** → im Ordner Programme „QR Keyboard Host.app"
   auswählen. Der Menüpunkt **„Bedienungshilfen öffnen…"** in der App führt
   direkt dorthin.)
3. App einmal beenden und neu starten — im Menü steht dann
   **„Bedienungshilfen: ✓ erteilt"**.

Außerdem, falls macOS danach fragt bzw. die Firewall aktiv ist:

- **Lokales Netzwerk** für die App erlauben (Abfrage ab macOS 15).
- *Systemeinstellungen → Netzwerk → Firewall → Optionen* → eingehende
  Verbindungen für „QR Keyboard Host" erlauben.

Ausführliche Schritte mit Troubleshooting: [SETUP.md](SETUP.md).

## 4. iOS-App (Scanner) installieren

Die iPhone-App ist **derzeit nicht im App Store**. Sie wird mit Xcode und einem
eigenen (auch kostenlosen) Apple-Developer-Account auf das iPhone installiert —
die Schritt-für-Schritt-Anleitung dazu steht in [SETUP.md](SETUP.md), Abschnitt
„iOS-App aufs iPhone bringen".

## 5. Loslegen

1. Mac und iPhone ins **selbe WLAN**.
2. iOS-App öffnen → sie findet den Mac automatisch („Verbunden mit …").
3. Am Mac den Cursor in ein Textfeld setzen, Code scannen → der Text wird sofort
   getippt.

**Wichtig:** Die Verbindung ist bewusst unverschlüsselt und ohne Anmeldung —
die App nur in vertrauenswürdigen Netzen betreiben und beenden, wenn sie nicht
gebraucht wird. Details: [SECURITY.md](../SECURITY.md).
