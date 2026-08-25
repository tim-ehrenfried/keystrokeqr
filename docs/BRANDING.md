# Branding & Naming Spec (authoritative)

As of v0.7.0 the product is called **KeystrokeQR**. This file is the **single
source of truth** for all names, IDs, and identifiers — the macOS host and iOS
client must match exactly (Bonjour service type, bundle prefix, etc.),
otherwise they won't discover/pair.

## Product names (display)

| Context | Name |
|---|---|
| Brand / repo / umbrella term | **KeystrokeQR** |
| iOS app (Home Screen name, store title) | **KeystrokeQR** |
| macOS menu bar app | **KeystrokeQR Host** |

Legacy names being fully replaced: "QR-Keyboard", "QR Keyboard Scanner",
"QR Keyboard Host", "qr-keyboard".

## Bundle identifiers

| Target | Bundle ID |
|---|---|
| iOS app | `de.timehrenfried.keystrokeqr` |
| iOS widget extension | `de.timehrenfried.keystrokeqr.widgets` |
| macOS host | `de.timehrenfried.keystrokeqr.host` |

## Other identifiers (MUST be identical on host & client)

| Purpose | Value (old → new) |
|---|---|
| Bonjour service type | `_qr-keyboard._tcp` → **`_keystrokeqr._tcp`** |
| URL scheme (iOS deep link) | `qrkeyboard://` → **`keystrokeqr://`** (scan link: `keystrokeqr://scan`) |
| Keychain service iOS | `de.timehrenfried.qr-keyboard-scanner` → **`de.timehrenfried.keystrokeqr`** |
| Keychain service macOS | `de.timehrenfried.qr-keyboard-host` → **`de.timehrenfried.keystrokeqr.host`** |
| Bonjour TXT version | stays `v=2` (protocol unchanged) |

> Note: the service type, bundle IDs, and keychain services change — existing
> pairings from v0.6.x must be redone **once**. That's acceptable for a
> rebrand (both apps ship together).

## Repository / paths

- GitHub: `github.com/tim-ehrenfried/keystrokeqr` (already renamed)
- Local: `/Users/timehrenfried/DEV/TOOLS/keystrokeqr` (already renamed)
- All README/badge/docs links point to the new repo name.

## Internal Swift symbols (recommended, not strictly required to match)

Xcode target names and folders may stay as they are (`QRKeyboardScanner`,
`QRKeyboardHost`) to avoid unnecessarily restructuring the pbxproj/SPM setup —
a rename may **only** happen if it can be done cleanly and build-verified.
The priority is that the **user-visible** names and the **IDs** above are
correct. The product name (display) is set via
`PRODUCT_NAME`/`INFOPLIST_KEY_CFBundleDisplayName` or `CFBundleName`, not via
the target name.

## Internationalization (i18n)

- **Development/base language: English (`en`).** Additional localization: German (`de`).
- iOS: string catalog (`Localizable.xcstrings`) + localized Info.plist keys
  (`InfoPlist.xcstrings` for usage descriptions/display name). All user-visible
  SwiftUI strings via `String(localized:)`/catalog.
- macOS: `Localizable.strings`/string catalog for menu, pairing, and status texts; base = en.
- New user-visible text is maintained bilingually (en first, de as an equal).

## Official vs. community builds (since v0.16.0)

Official builds — the ones **we** ship (GitHub releases, App Store) — embed
personal/infrastructure references: the contact email
(mail@tim-ehrenfried.de), the landing page (keystrokeqr.tim-ehrenfried.de,
including the `/ios` App-Store QR in the Mac onboarding and the `/mac`
"download the newest host" link in the iOS app). Anyone building from this
repo gets a **neutral community build**: those references are compiled out
(About shows "Community build — source & issues on GitHub" instead); only the
GitHub repository link remains, since it *is* the source.

Mechanism: the Swift compilation condition **`OFFICIAL_BUILD`**, read by
`BrandingConfig.swift` on both platforms. It is **off by default** and only
set by our own pipeline:

| Build | How the flag is set |
|---|---|
| macOS (Make) | `make app OFFICIAL=1` / `make dmg OFFICIAL=1` (the release workflow does this) |
| iOS (xcodebuild) | `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OFFICIAL_BUILD'` (our device/App-Store builds) |
| CI build check | intentionally **neutral** — it verifies the community path |

Non-repo dependencies of ours (the landing page, releases infrastructure) are
therefore never baked into third-party builds.

## App icon (since v0.14.0)

The single source of truth for the app icon is **`branding/logo-master.png`**
(3D-rendered QR tile with a white "K", on a pure-black canvas). All variants
are derived from it — never edit a derived file directly:

| Variant | File | Built by |
|---|---|---|
| iOS / App Store (full-bleed 1024, no alpha) | `ios/…/AppIcon.appiconset/AppIcon-1024.png`, `branding/appstore-1024.png` | `ios/make-icon.sh` |
| macOS (`.icns`, Apple margin + shadow, transparent corners) | `macos/Support/AppIcon.icns` | `macos/Support/make-icon.sh` |
| DMG window background (logo + arrow) | `macos/Support/dmg-background.png` | `macos/Support/make-dmg-background.sh` (`make dmg-bg`) |
| DMG volume icon | uses the macOS `.icns` | `macos/Support/make-dmg.sh` |
| Monochrome UI variants (luminance → alpha) | `branding/logo-mono-white-1024.png`, `logo-mono-black-1024.png` | one-off from master |
| Website (landing page) | `assets/icon.png` on the `gh-pages` branch | copy of `appstore-1024.png` |

## Version

This rebrand batch step is released as **v0.7.0** (in both targets:
`MARKETING_VERSION` and `CFBundleShortVersionString`).
