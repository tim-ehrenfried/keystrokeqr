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
after completion. The flow can be reopened at any time from Settings
("Show the intro again").

## Required permissions

| Permission | Purpose |
| --- | --- |
| **Camera** (`NSCameraUsageDescription`) | Scanning QR/barcodes. If denied, the app shows a hint with a link to Settings. |
| **Local network** (`NSLocalNetworkUsageDescription` + `NSBonjourServices = _keystrokeqr._tcp`) | Bonjour discovery of the Mac and the direct WebSocket connection. iOS asks on the first scan start; if denied, no Mac is found (can be changed later under Settings → Apps → KeystrokeQR → Local Network). |

## Features

- Full-screen viewfinder, status capsule (Searching / Connecting / Connected / Disconnected).
- **Scan window (region of interest):** only a square 1:1 cutout scans — full
  screen width, horizontally centered, its center slightly above the middle of
  the screen (~43 % of the screen height). The rest of the camera image is
  dimmed but still visible (translucent black overlay, rounded corners, yellow
  viewfinder corner brackets). Detection is restricted to the window via
  `AVCaptureMetadataOutput.rectOfInterest`
  (`metadataOutputRectConverted(fromLayerRect:)`, recomputed after session
  start and on every layout pass); codes outside are ignored, outlines only
  appear inside. Tap-to-focus and pinch-to-zoom keep working on the whole
  preview.
- Supported symbologies: QR, EAN-8/13, Code 128/39/93, PDF417, DataMatrix,
  Aztec, Interleaved 2/5, ITF-14, UPC-E.
- Outlines around all currently detected codes in the scan window (like the
  system scanner), smoothly tracking, with a short fade-out when they leave
  the frame — yellow for the selected (center-most) code, subtle white for
  the others.
- **Two send modes** (Settings → Sending, persisted):
  - **Push to send (default):** the scanner detects codes live (outlines +
    "Last detected" preview) but sends nothing automatically. While a code is
    in the scan window, a round yellow shutter-style send button appears above
    the control bar. **Hold it briefly** (~0.3 s, in the style of the Lock
    Screen flashlight/camera buttons: subtle haptic on press, visible ring progress,
    a firm haptic "pop" on trigger) to send the detected code exactly once —
    keeping it held does NOT repeat, and a short cooldown (~0.9 s) prevents
    double triggers. A too-short tap shows a "Hold to send" hint instead. The
    button fades out ~2 s after the code leaves the frame. Codes already sent
    in this session are marked subtly ("Already sent") next to the preview and
    may deliberately be sent again.
  - **Continuous:** the previous behavior — each code is typed automatically
    once (viewfinder freeze + 1 s cooldown on detection). When the same code
    is scanned again, the yellow **"Send again"** trigger appears instead,
    also hold-to-trigger, for deliberate repetition.
- **Haptics & sound:** "Haptics on send" (default ON) plays success/error
  feedback when a code is actually sent; "Sound on send" (default OFF) plays
  a short, clearly audible scanner-style beep (system sound 1052,
  AudioToolbox, respects the silent switch).
- **Aiming with multiple codes:** if several codes are visible in the scan
  window at once, the code whose center is closest to the center of the scan
  window deterministically wins — it feeds the candidate/preview/send button
  (push to send) as well as auto-send (continuous). The chosen code gets the
  yellow outline, all other visible codes a subtle dimmed white one, so you
  can "aim" by moving the phone.
- **Settings** (gear in the control bar) bundle everything: send mode picker,
  Auto-Enter, Auto-Tab, haptics/sound, clear history (with confirmation),
  "Manage paired Macs", plus **Help** and **About** as sub-pages and "Show the
  intro again". The bottom control bar itself stays slim: last detected/scanned
  text, Mac picker button, settings button.
- "Clear history" resets the send-once list; on app restart it is cleared
  automatically (no persistence).
- Best rear camera as a virtual device (Triple → DualWide → Dual → Wide):
  automatic lens switching including macro for close codes; continuous
  autofocus with a near-range preference, **tap-to-focus** (yellow frame), and
  **pinch-to-zoom** (up to 10x).
- Consistently dark design including a dark launch screen and dark loading
  state until the camera delivers frames.
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
  `updatesFrequently`), the send button ("Send: …"), "Send again",
  "Clear history", "Pair Mac", "Choose Mac", Settings, the settings toggles,
  and the onboarding/pairing navigation. The hold-to-trigger buttons are
  activatable directly via the default VoiceOver action (no hold required).
  Decorative symbols are `accessibilityHidden`, headings are marked as
  `.isHeader`; the scan-window overlay is decorative and hidden from
  accessibility.
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

## Official vs. community builds

Official builds (built/signed by the maintainer or CI) contain personal
contact and infrastructure references: the contact e-mail, the landing page
and the "Download the latest Mac host" link
(`https://keystrokeqr.tim-ehrenfried.de/mac`) in About and Help. Builds made
by third parties from this repository stay **neutral**: none of these
references are compiled into the binary; About shows
"Community build — source & issues on GitHub" instead. The GitHub repository
link is deliberately **not** gated — it points to this source code (MIT) and
is correct in every build.

All gated values live in
[`QRKeyboardScanner/BrandingConfig.swift`](QRKeyboardScanner/BrandingConfig.swift)
behind the Swift compilation condition `OFFICIAL_BUILD`. The project does
**not** set this flag anywhere — a default build is always a neutral
community build. Official builds pass the flag from the outside (note the
`$(inherited)` so the Debug `DEBUG` condition is preserved):

```sh
xcodebuild -project QRKeyboardScanner.xcodeproj \
  -scheme QRKeyboardScanner \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OFFICIAL_BUILD'
```

## Version

`0.16.0` (`MARKETING_VERSION` in the app, widget and test targets, Debug + Release).
