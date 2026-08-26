# App Store Metadata — ready to paste

All texts for the App Store Connect record (Phase 2 of
[RELEASE-PHASE.md](RELEASE-PHASE.md)). English is the primary locale, German
the second. Character limits are noted per field.

## Basics

| Field | Value |
|---|---|
| App name (30) | `KeystrokeQR` |
| Subtitle EN (30) | `Scan on iPhone, type on Mac` |
| Subtitle DE (30) | `iPhone scannt, Mac tippt` |
| Bundle ID | `de.timehrenfried.keystrokeqr` |
| SKU | `keystrokeqr-ios` |
| Primary category | Utilities |
| Secondary category | Productivity |
| Price | Free |
| Age rating | 4+ (no sensitive content) |
| Support URL | `https://keystrokeqr.tim-ehrenfried.de/support.html` |
| Privacy policy URL | `https://keystrokeqr.tim-ehrenfried.de/privacy.html` |
| Copyright | `© 2026 Tim Ehrenfried` |

> The two URLs must be live before submission (Phase 5 DNS/Pages), or use the
> GitHub Pages default URL temporarily.

## Description — English (max 4000)

```
Point your iPhone at any QR code or barcode — and the text appears instantly
at your Mac's cursor, typed as real keystrokes.

KeystrokeQR turns your iPhone into a wireless barcode scanner for your Mac.
No cloud, no account, no browser extension: both devices talk directly to
each other over your local Wi-Fi, end-to-end encrypted and paired once with
a code shown on your Mac.

HOW IT WORKS
• Run the free KeystrokeQR Host app on your Mac (menu bar)
• Pair once with a 6-digit code
• Put the cursor in any text field, scan a code, hold the shutter — done

BUILT FOR REAL WORK
• Types into any app and any field — real, layout-independent keystrokes
• QR plus common 1D/2D barcodes (EAN, Code 128, DataMatrix, PDF417, …)
• Aiming scan window: the code closest to the center wins
• Push-to-send by default: nothing is sent until you hold the trigger
• Continuous mode for high-volume scanning (once per code, resend on demand)
• Optional Auto-Tab / Auto-Enter after each scan — perfect for forms
• Adjustable typing speed on the Mac for slow target fields
• Optional confirm-before-typing mode on the Mac
• Lock Screen widget, Control Center control, Action button & Siri support

PRIVATE BY DESIGN
• Everything stays on your Wi-Fi — there is no server and no data collection
• End-to-end encrypted, only explicitly paired devices can send
• Free & open source (MIT)

REQUIREMENTS
KeystrokeQR needs the free Mac companion app "KeystrokeQR Host"
(macOS 13 or newer) — download at keystrokeqr.tim-ehrenfried.de.
```

## Description — German (max 4000)

```
Richte dein iPhone auf einen QR- oder Barcode — und der Text erscheint sofort
an der Cursor-Position auf deinem Mac, getippt als echte Tastenanschläge.

KeystrokeQR macht dein iPhone zum kabellosen Barcode-Scanner für deinen Mac.
Keine Cloud, kein Konto, keine Browser-Erweiterung: Beide Geräte sprechen
direkt über dein WLAN miteinander — Ende-zu-Ende verschlüsselt und einmalig
per Code gekoppelt.

SO FUNKTIONIERT'S
• Kostenlose Mac-App „KeystrokeQR Host" starten (Menüleiste)
• Einmalig mit 6-stelligem Code koppeln
• Cursor in ein Textfeld setzen, Code scannen, Auslöser halten — fertig

FÜR ECHTE ARBEIT GEBAUT
• Tippt in jede App und jedes Feld — echte, layoutunabhängige Anschläge
• QR plus gängige 1D/2D-Barcodes (EAN, Code 128, DataMatrix, PDF417, …)
• Scan-Fenster mit Zielen: der mittigste Code gewinnt
• Push-to-Send als Standard: gesendet wird erst beim Halten des Auslösers
• Kontinuierlicher Modus fürs Massen-Scannen (einmal pro Code, erneut auf Wunsch)
• Optional Auto-Tab / Auto-Enter nach jedem Scan — ideal für Formulare
• Einstellbare Tippgeschwindigkeit am Mac für langsame Zielfelder
• Optionaler Bestätigen-vor-Tippen-Modus am Mac
• Sperrbildschirm-Widget, Kontrollzentrum, Action Button & Siri

PRIVAT BY DESIGN
• Alles bleibt in deinem WLAN — kein Server, keine Datenerhebung
• Ende-zu-Ende verschlüsselt, nur gekoppelte Geräte können senden
• Kostenlos & Open Source (MIT)

VORAUSSETZUNG
KeystrokeQR braucht die kostenlose Mac-App „KeystrokeQR Host"
(macOS 13 oder neuer) — Download auf keystrokeqr.tim-ehrenfried.de.
```

## Keywords (max 100 chars, comma-separated, no spaces needed)

EN: `qr,barcode,scanner,keyboard,wedge,mac,type,inventory,warehouse,scan,productivity,hid`
DE: `qr,barcode,scanner,tastatur,mac,tippen,inventur,lager,scannen,eingabe,produktiv`

## Promotional text (max 170, editable without review)

EN: `Scan a code on your iPhone — it's typed instantly on your Mac. Local-only, encrypted, open source. Requires the free Mac companion app.`
DE: `Code mit dem iPhone scannen — sofort am Mac getippt. Nur im lokalen WLAN, verschlüsselt, Open Source. Benötigt die kostenlose Mac-App.`

## What's New (first release)

EN: `First public release.`
DE: `Erste öffentliche Version.`

## App privacy

**Data not collected** — select "No" for all data-collection questions.
Matches privacy.html (no analytics, no accounts, no servers).

## App Review notes (paste into "Notes" + attach demo video)

```
IMPORTANT CONTEXT FOR REVIEW

KeystrokeQR is a companion app: the iPhone scans QR/barcodes and sends the
decoded text — over the LOCAL Wi-Fi network only, end-to-end encrypted — to
a free, open-source macOS menu-bar app ("KeystrokeQR Host"), which types the
text at the Mac's cursor position. There is no server component.

Without the Mac companion on the same Wi-Fi, the app shows the scanner but
has nothing to send to — this is by design. Please see the attached demo
video showing the full flow (pairing with a one-time code, scanning,
text appearing on the Mac).

Mac companion (free, open source, MIT):
https://keystrokeqr.tim-ehrenfried.de  /  https://github.com/tim-ehrenfried/keystrokeqr

The app collects no data, has no accounts, and uses the camera solely for
on-device code detection. Local Network permission is required for Bonjour
discovery of the user's own Mac.
```

## Screenshots (per device size: 6.9"/6.7" required; 6.5"/6.1" optional)

Plan — five shots, dark UI, real content:
1. Scanner with scan window + yellow shutter (hero), caption "Scan on iPhone, type on your Mac"
2. Code detected + outline + "hold to send", caption "Nothing sends until you say so"
3. Pairing screen with code, caption "Paired once, encrypted always"
4. Settings sheet, caption "Auto-Enter, Auto-Tab, modes, sounds"
5. Lock Screen widget/control, caption "Start scanning from your Lock Screen"

Captions can be baked into framed screenshots or left off (plain screenshots
are fine for v1). German versions: same shots, DE locale.
```
