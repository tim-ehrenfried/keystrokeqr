# Branding- & Naming-Spec (verbindlich)

Ab v0.7.0 heißt das Produkt **KeystrokeQR**. Diese Datei ist die **einzige Quelle der
Wahrheit** für alle Namen, IDs und Bezeichner — macOS-Host und iOS-Client müssen exakt
übereinstimmen (Bonjour-Service-Typ, Bundle-Präfix etc.), sonst finden/koppeln sie nicht.

## Produktnamen (Anzeige)

| Kontext | Name |
|---|---|
| Marke / Repo / Dachbegriff | **KeystrokeQR** |
| iOS-App (Home-Screen-Name, Store-Titel) | **KeystrokeQR** |
| macOS-Menüleisten-App | **KeystrokeQR Host** |

Altnamen, die vollständig ersetzt werden: „QR-Keyboard", „QR Keyboard Scanner",
„QR Keyboard Host", „qr-keyboard".

## Bundle-Identifier

| Target | Bundle-ID |
|---|---|
| iOS-App | `de.timehrenfried.keystrokeqr` |
| iOS-Widget-Extension | `de.timehrenfried.keystrokeqr.widgets` |
| macOS-Host | `de.timehrenfried.keystrokeqr.host` |

## Weitere Bezeichner (MÜSSEN Host & Client gleich sein)

| Zweck | Wert (alt → neu) |
|---|---|
| Bonjour-Service-Typ | `_qr-keyboard._tcp` → **`_keystrokeqr._tcp`** |
| URL-Scheme (iOS Deep-Link) | `qrkeyboard://` → **`keystrokeqr://`** (Scan-Link: `keystrokeqr://scan`) |
| Keychain-Service iOS | `de.timehrenfried.qr-keyboard-scanner` → **`de.timehrenfried.keystrokeqr`** |
| Keychain-Service macOS | `de.timehrenfried.qr-keyboard-host` → **`de.timehrenfried.keystrokeqr.host`** |
| Bonjour-TXT-Version | bleibt `v=2` (Protokoll unverändert) |

> Hinweis: Service-Typ, Bundle-IDs und Keychain-Services ändern sich — bestehende
> Kopplungen aus v0.6.x müssen **einmal neu** durchgeführt werden. Das ist bei einem
> Rebrand akzeptiert (beide Apps werden gemeinsam ausgeliefert).

## Repository / Pfade

- GitHub: `github.com/tim-ehrenfried/keystrokeqr` (bereits umbenannt)
- Lokal: `/Users/timehrenfried/DEV/TOOLS/keystrokeqr` (bereits umbenannt)
- Alle README-/Badge-/Doku-Links auf den neuen Repo-Namen.

## Interne Swift-Symbole (empfohlen, nicht zwingend gleichlautend)

Xcode-Target-Namen und Ordner dürfen bleiben (`QRKeyboardScanner`, `QRKeyboardHost`),
um die pbxproj-/SPM-Struktur nicht unnötig umzubauen — **nur** wenn eine Umbenennung
sauber und build-verifiziert möglich ist, darf sie erfolgen. Priorität hat, dass die
**nutzersichtbaren** Namen und die **IDs** oben stimmen. Product-Name (Anzeige) wird über
`PRODUCT_NAME`/`INFOPLIST_KEY_CFBundleDisplayName` bzw. `CFBundleName` gesetzt, nicht über
den Target-Namen.

## Internationalisierung (i18n)

- **Development/Basissprache: Englisch (`en`).** Zusätzliche Lokalisierung: Deutsch (`de`).
- iOS: String Catalog (`Localizable.xcstrings`) + lokalisierte Info.plist-Keys
  (`InfoPlist.xcstrings` für Usage-Descriptions/Display-Name). Alle nutzersichtbaren
  SwiftUI-Strings über `String(localized:)`/Catalog.
- macOS: `Localizable.strings`/String-Catalog für Menü-, Pairing- und Statustexte; base = en.
- Neuer nutzersichtbarer Text wird zweisprachig gepflegt (en zuerst, de gleichwertig).

## Version

Dieser Rebrand-Sammelschritt wird **v0.7.0** (in beiden Targets: `MARKETING_VERSION`
bzw. `CFBundleShortVersionString`).
