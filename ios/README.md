# KeystrokeQR (iOS)

SwiftUI app for iPhone (iOS 17+, portrait) that scans QR and barcodes and sends
their contents via WebSocket to the KeystrokeQR Mac app on the local network.
The Mac is discovered automatically via Bonjour (`_keystrokeqr._tcp`); the port
always comes from the Bonjour resolution. The connection is end-to-end
encrypted and requires a one-time pairing (OTP code on the Mac) — see
[`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md) (protocol v1:
[`../docs/PROTOCOL.md`](../docs/PROTOCOL.md)). All names/IDs are defined in
[`../docs/BRANDING.md`](../docs/BRANDING.md).

> The Xcode target/folder name remains `QRKeyboardScanner` for compatibility
> reasons; the user-visible display name and all bundle IDs, however, are
> **KeystrokeQR** (see BRANDING.md).

## Build & Run

### Xcode

1. Open `QRKeyboardScanner.xcodeproj` in Xcode (16 or newer).
2. The scheme **QRKeyboardScanner** is included as a shared scheme and offered
   automatically.
3. Choose a destination (simulator or iPhone) and **Run** (⌘R).

> **Simulator note:** The simulator has no camera — scanning only works on a
> real iPhone. Bonjour/WebSocket do work in the simulator.

### Real iPhone (signing)

To run on a real device, a signing team must be selected in Xcode: target
**QRKeyboardScanner** → tab **Signing & Capabilities** → choose a
**Team** (a personal Apple ID team is enough for development).
The project deliberately ships **without** `DEVELOPMENT_TEAM` in the
repository; the bundle IDs are `de.timehrenfried.keystrokeqr` (app) and
`de.timehrenfried.keystrokeqr.widgets` (widget extension).

### Command line (no signing, simulator)

```sh
xcodebuild -project QRKeyboardScanner.xcodeproj \
  -scheme QRKeyboardScanner \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

## Language & localization (i18n)

- **Base language: English (`en`)**, with **German (`de`)** in addition.
- All user-visible SwiftUI strings go through the string catalog
  [`Shared/Localizable.xcstrings`](Shared/Localizable.xcstrings) (member of
  both the app and widget targets). Permission/display-name texts of the
  Info.plist live in [`QRKeyboardScanner/InfoPlist.xcstrings`](QRKeyboardScanner/InfoPlist.xcstrings).
- `developmentRegion = en`, `knownRegions = en, de`. New texts are maintained
  bilingually (English first, German as an equal).

## First-run onboarding

On the very first launch, a multi-step onboarding flow appears once
([`QRKeyboardScanner/OnboardingView.swift`](QRKeyboardScanner/OnboardingView.swift))
in the dark app design: welcome → how it works (local, encrypted, no
cloud) → permissions (the camera prompt is triggered contextually here, local
network is announced) → pairing. Persisted via `@AppStorage`
(`didCompleteOnboarding`); camera access and Bonjour discovery start only
after completion. The flow can be reopened at any time from Help
("Show the intro again").

## Required permissions

| Permission | Purpose |
| --- | --- |
| **Camera** (`NSCameraUsageDescription`) | Scanning QR/barcodes. If denied, the app shows a hint with a link to Settings. |
| **Local network** (`NSLocalNetworkUsageDescription` + `NSBonjourServices = _keystrokeqr._tcp`) | Bonjour discovery of the Mac and the direct WebSocket connection. iOS asks on the first scan start; if denied, no Mac is found (can be changed later under Settings → Apps → KeystrokeQR → Local Network). |

## Features

- Full-screen viewfinder, status capsule (Searching / Connecting / Connected / Disconnected).
- Supported symbologies: QR, EAN-8/13, Code 128/39/93, PDF417, DataMatrix,
  Aztec, Interleaved 2/5, ITF-14, UPC-E.
- On detection: haptic feedback, the viewfinder freezes briefly, exactly 1 s cooldown.
- Yellow outlines around all currently detected codes in the viewfinder (like
  the system scanner), smoothly tracking, with a short fade-out when they leave
  the frame.
- **Send-once:** Each code is typed automatically only once. When the same code
  is scanned again, a yellow **"Send again"** trigger appears instead, for
  deliberate repetition. "Clear history" (⟲) resets the list; on app restart
  it is cleared automatically (no persistence).
- Best rear camera as a virtual device (Triple → DualWide → Dual → Wide):
  automatic lens switching including macro for close codes; continuous
  autofocus with a near-range preference, **tap-to-focus** (yellow frame), and
  **pinch-to-zoom** (up to 10x).
- Consistently dark design including a dark launch screen and dark loading
  state until the camera delivers frames.
- **Auto-Enter** / **Auto-Tab** toggles (persisted), display of the last
  scanned text, in-app help.
- Automatic reconnect on connection loss; a picker list when multiple Macs
  are found.
- If the Mac reports `accessibility_denied`, the app shows a clear notice.
- **Pairing:** When a new, encrypted Mac (`v=2`) is found, a pairing screen
  appears automatically (6-digit OTP from the Mac menu "Pair device…"). After
  success, the app connects automatically and end-to-end encrypted;
  "Manage paired Macs" (Help) allows unpairing. Pure v1 hosts show the
  "Please update the Mac app" notice.

## Quick start from the Lock Screen

The app ships a widget extension (`QRKeyboardScannerWidgets`) and App
Intents; all paths open the app directly in the scanner (deep link
`keystrokeqr://scan`):

- **Lock Screen widget (iOS 17+):** press and hold the Lock Screen →
  *Customize* → Lock Screen → tap the widget area → add **KeystrokeQR**
  (circular or rectangular). There is also a small Home Screen widget.
- **Lock Screen quick controls / Control Center (iOS 18+):** while
  customizing the Lock Screen, replace one of the bottom quick controls
  (flashlight/camera) with the **"Scan QR Code"** control — or place the
  control in Control Center (control widget).
- **Action Button (iPhone 15 Pro+):** Settings → *Action Button* →
  *Shortcut* → **"Scan QR Code"**.
- **Siri/Spotlight/Shortcuts:** The "Scan QR Code" App Intent is available in
  the Shortcuts app; Siri phrase e.g. "Scan QR Code with KeystrokeQR".

Under the hood: URL scheme `keystrokeqr` (`keystrokeqr://scan`),
`StartScanIntent` (AppIntent, `openAppWhenRun`) + `AppShortcutsProvider` in
the app target, widget extension with Lock Screen/Home Screen widgets
(`.widgetURL`) and an iOS 18 ControlWidget (bundle ID
`de.timehrenfried.keystrokeqr.widgets`, deployment iOS 17, ControlWidget
`@available(iOS 18)`-gated).

## Export compliance (App Store / TestFlight)

The app's Info.plist sets `ITSAppUsesNonExemptEncryption` = `NO`. Only
standard cryptography from Apple's **CryptoKit** is used
(HKDF-SHA256, HMAC-SHA256, ChaChaPoly, Curve25519) — solely to secure the
local pairing/session (see [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md)).
This falls under the exemption in the US export regulations, so the export
compliance prompt is skipped on every TestFlight/App Store upload. The widget
extension uses no crypto of its own and therefore doesn't need the flag.

## Accessibility & Dynamic Type

- User-visible controls carry VoiceOver labels/hints/traits: the status
  capsule (as one element "Connection status: …", decorative dot hidden,
  `updatesFrequently`), "Send again", "Clear history", "Pair Mac",
  "Choose Mac", Help, the Auto-Enter/Auto-Tab toggles, and the
  onboarding/pairing navigation. Decorative symbols are
  `accessibilityHidden`, headings are marked as `.isHeader`.
- Texts use semantic fonts (scaling with Dynamic Type); where space is tight,
  `lineLimit`/`minimumScaleFactor` or
  `fixedSize(horizontal:false, vertical:true)` keep the layout from breaking
  at large text sizes.
- Empty/error states: with an empty list, the Mac picker shows a hint
  ("No Mac found yet. Are the iPhone and Mac on the same Wi-Fi, and is the
  KeystrokeQR Mac app running?"); the camera-denied screen is fully
  accessible.

## Tests

A unit test target **`QRKeyboardScannerTests`** (in the same hand-written
`project.pbxproj` style, `objectVersion 77`, its own
`FileSystemSynchronizedRootGroup`) covers the crypto/protocol core logic and
is hooked into the test action of the shared scheme:

- `CryptoManagerTests` — HKDF derivations with the exact salt/info strings
  (`qrkb-pair-v2`, `qrkb-confirm-v2`, `qrkb-session-v2`), Curve25519 PSK
  agreement on both sides, pairing HMAC, the 12-byte nonce scheme
  (direction prefix ‖ big-endian `seq`), and ChaChaPoly frame round trips
  including tampering/replay/direction failures.
- `MessagesCodableTests` — wire format of the protocol messages (`scan`, `ack`,
  `enc`, `pair_*`, `session_*`).

Run them:

```sh
xcodebuild test -project QRKeyboardScanner.xcodeproj \
  -scheme QRKeyboardScanner -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

(27 tests, green; replace `iPhone 17 Pro` with a simulator available via
`xcrun simctl list devices available` if needed.)

## Version

`0.14.0` (`MARKETING_VERSION` in the app and widget targets, Debug + Release).
