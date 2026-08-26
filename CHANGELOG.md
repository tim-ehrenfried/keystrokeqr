# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/).

## [0.16.1] – 2026-08-26 (macOS only)

### Changed
- **Release DMGs are now signed with a Developer ID and notarized by Apple** (hardened runtime, secure timestamp, stapled ticket) — the Gatekeeper "unverified developer / potentially malicious" warning is gone for this and all future releases. Community builds from source are unaffected.

## [0.16.0] – 2026-08-25

### Added
- **Official vs. community builds**: builds we ship embed the official branding (contact email, landing-page links, App-Store QR); anyone building from the repo gets a neutral community build with those references compiled out (`OFFICIAL_BUILD` flag via `BrandingConfig` on both platforms — set by `make … OFFICIAL=1` and our release pipeline, never by default; verified via binary string checks). See [docs/BRANDING.md](docs/BRANDING.md).
- **Cross-promotion (official builds)**: the Mac onboarding (and panel help) shows a scannable QR code leading to the iPhone app (`…/ios`, redirects to the App Store once live); the iOS app links to "Download the latest Mac host" (`…/mac` → latest release). Landing page gained the `/ios` and `/mac` redirect stubs.
- **iOS – aiming**: when several codes are visible in the scan window, the one closest to the window center is chosen deterministically (yellow outline; other codes dimmed white) — aim by moving the phone.

### Changed
- **iOS – hold-to-send duration** shortened to 0.3 s; **send sound** is now a crisp scanner-style beep (SystemSound 1052) instead of the dull tock. Auto-Enter confirmed off by default.

## [0.15.0] – 2026-08-25 (iOS only)

### Added
- **Push-to-send mode (new default)**: the scanner keeps detecting codes live, but nothing is sent automatically anymore. As soon as a code is inside the scan window, a round yellow shutter button appears — **hold it (~0.45 s) until the haptic "pop"** to send exactly once (Lock-Screen-button behavior: a short tap shows a "Hold to send" hint instead of sending, holding longer never repeats). The previous behavior lives on as the "Continuous" mode (auto-send once per code + "Send again" trigger, now also hold-to-trigger).
- **Send feedback settings**: haptic feedback on send (default on) and an optional short sound (default off, respects the silent switch).
- **Scan window**: only a full-width 1:1 square slightly above the screen center actively scans; the rest of the camera view is dimmed (translucent black) with rounded corners and yellow viewfinder brackets. Detection is technically restricted to the window (`rectOfInterest`); tap-to-focus and pinch-to-zoom still work everywhere.
- **Settings screen**: the help button became a gear — a dedicated dark settings sheet now bundles everything (send mode, Auto-Enter, Auto-Tab, haptics, sound, clear history, manage paired Macs) with **Help**, **About**, and "Show the intro again" as subpages. The Auto-Enter/Auto-Tab toggles left the bottom bar, which is now much slimmer.

## [0.14.0] – 2026-08-25

### Changed
- **New brand icon set**: the 3D-rendered QR tile with the white "K" (`branding/logo-master.png`) is now the single source of truth for all icons — iOS/App Store (full-bleed 1024), macOS `.icns` (Apple margin, rounded mask, soft shadow), the DMG window background (logo + arrow), the DMG **volume icon**, monochrome UI variants (white/black on transparent), and the landing page. Both `make-icon.sh` scripts derive everything from the shared master (see the icon table in [docs/BRANDING.md](docs/BRANDING.md)).
- **Documentation fully in English**: README, SECURITY, CHANGELOG (all historical entries), and all docs/ guides plus the platform READMEs were translated for the public release; stale claims fixed along the way (the connection has been end-to-end encrypted and pairing-gated since v0.6.0; version references brought up to date).

## [0.13.2] – 2026-08-25 (macOS only)

### Fixed
- **macOS – Intro window hugged the left/right edges**: Same effect as previously in the control panel — the page stack (`.centerX`) had no explicit width, so the window width shrank to the card width and the margins disappeared. Both onboarding pages now have a fixed width including both 28 pt margins.

## [0.13.1] – 2026-08-25 (macOS only)

### Fixed
- **macOS – Crash/hang when opening the introduction**: The setup assistant called `updateAccessibility()` in the middle of the lazy construction of `setupView`, and that method references `setupView` itself → re-entrant access to the unfinished lazy initializer = infinite recursion. The redundant call was removed (the status is set after construction). Verified via forced onboarding at launch: the app stays stable.
- **macOS – Device list truncated "paired since …" (German)**: The longer German "Umbenennen/Entfernen" buttons pushed the date out of view. Rename/Remove are now compact, language-neutral icon buttons (pencil/trash, with tooltip + VoiceOver label); the date is no longer truncated.

## [0.13.0] – 2026-08-25 (macOS only)

### Fixed
- **macOS – Panel was cut off on the right**: The home view had no right margin (the card sat flush against the window edge). Now fixed, symmetric insets (left = right = top = bottom), with the window width calculated including the right margin.

### Changed
- **macOS – Setup assistant streamlined**:
  - The Accessibility status is now **checked live** (timer + on window focus) and turns green ("Accessibility enabled ✓") once granted — without a restart.
  - Once the permission is granted, the "Open Accessibility…" button disappears; the final action is **"Pair device"** instead of "Get started" (disabled until the permission is granted, with an explanatory hint).
  - After successful pairing, the assistant briefly shows **"Successfully paired!"** with **"Get started"** and then jumps to the control panel. Pairing outside the assistant behaves unchanged (auto-close only, no jump).

## [0.12.0] – 2026-08-25

### Changed
- **macOS – "Typed" HUD redesigned**: now sits bottom-center (~20% of screen height from the bottom) and has a modern, clean look (solid dark card instead of washed-out blur, yellow checkmark symbol, crisp text) — still focus-neutral.
- **macOS – Control panel in landscape**: home view is now two columns (~786 pt wide) instead of one tall single column; single-window navigation and auto-sizing without scrolling remain.
- **iOS – App icon aligned with macOS**: shared motif (QR viewfinder + keycap/caret + yellow scan line), the iOS icon rendered full-bleed from the same motif as the macOS icon (`ios/make-icon.sh`).

### Fixed
- **iOS – Pairing dialog closed again immediately after tapping in the Mac picker list**: sheet race between the picker list and the pairing screen; the selection is now applied only after the list has fully dismissed, and the auto-decline distinguishes a real swipe-dismiss from a programmatic sheet switch.

### Docs
- **docs/README.md**: navigation index for the documentation (installation, setup, protocol, security) for a clean entry point; linked from the root README.

## [0.11.0] – 2026-08-25

### Added
- **macOS – Start at login**: toggle in the panel (`SMAppService`), launches the host automatically on login.
- **macOS – "✓ Typed" HUD**: subtle, focus-neutral confirmation after every keystroke injection (non-activating panel, never steals focus).
- **macOS – Rename devices** in the paired-devices list.
- **macOS – "Confirm before typing" mode** (off by default): holds incoming scans and types only after confirmation; reactivates the originally focused app beforehand so the text lands in the right field.
- **Export compliance**: `ITSAppUsesNonExemptEncryption = NO` in the iOS app (standard crypto only) — no more compliance prompt on TestFlight/App Store uploads.
- **Accessibility**: VoiceOver labels/hints and Dynamic Type polish (iOS), plus accessibility labels + empty states (macOS panel).
- **Automated tests + CI**: crypto/protocol test suites (macOS SwiftPM 45 tests, iOS XCTest 27 tests — HKDF derivations, pairing HMAC, ChaChaPoly frames/nonce/replay, Codable wire format); the CI workflow runs both on every push/PR.

## [0.10.0] – 2026-08-25

### Changed
- **macOS – one window instead of three**: control panel, Help, and About are now a single window with internal navigation (back button); the window opens exactly at content size (no scrolling). "Show introduction" is a subtle gray button at the top right (no longer a blue link); the links in About/Help are icon buttons (GitHub/email/docs), as in the iOS app.
- **macOS – Pairing**: when the code expires, a new one is generated automatically (no more "New code" button), the countdown is reset, and a hint "Code expired – a new code was generated." is shown.

### Fixed
- **iOS – Pairing screen was unreachable after dismissal without restarting the app**: The screen kept popping up in a loop driven by the running discovery; the only way out was a restart. The app now remembers a deliberate decline (no automatic re-popup) AND offers an always-visible way back — a "Pair Mac" button in the scanner view (as soon as a Mac is found but not connected) and the Mac picker list both reopen the pairing screen.

## [0.9.0] – 2026-08-25

### Added
- **macOS – KeystrokeQR panel (control center)**: A styled window bundles the former menu items — connection status, **live Accessibility status** (green ✓ "Enabled" / red ✗, updates without a restart once granted), paired devices (with "Remove"), pairing, typing speed, Help, About, introduction. The menu bar menu is now slim as a result (including a ✓/✗ short status).
- **macOS – in-app Help** (quick start + troubleshooting + repo/docs links) and **About** (dynamic version, © 2026 Tim Ehrenfried, mail@tim-ehrenfried.de, GitHub, MIT).
- **iOS – multiple Macs & Mac switching**: list of all discovered Macs with status badges (Connected/Paired/New/Update), reachable at any time via a button; actively switching cleanly disconnects the current connection (no session-key leak between Macs) and connects/pairs to the chosen Mac.

### Fixed
- **After "Remove device" on the Mac, no (re)connection was possible**: The `session_error`/`not_paired` frame was lost due to the immediate connection close, leaving the iPhone stuck in a silent endless reconnect loop instead of offering re-pairing.
  - **macOS**: `not_paired`/`bad_session` are now closed only **after confirmed send** (`closeAfterSend`), so they reliably reach the client; "Remove device" also disconnects the active session immediately.
  - **iOS**: distinguishes host-side unpairing from a transient network drop (handshake-window heuristic as a fallback) → on `not_paired`, deletes the stale PSK and offers re-pairing directly instead of searching endlessly.

## [0.8.0] – 2026-08-25

### Added
- **macOS – adjustable typing speed**: "Typing Speed" menu (Fast / Normal / Slow) controls chunk size and pause in the KeyInjector so nothing gets dropped in the target field with lots of text; the choice is persistent and takes effect immediately.
- **macOS – first-launch onboarding**: styled welcome window on first launch (how it works, Accessibility button, "Pair device…"), reopenable via "Show Introduction".

### Changed
- **Pairing window (macOS) redesigned**: dark onboarding look, code in digit boxes, countdown bar, wordmark; closes automatically ~1.5 s after success.
- **iOS – Pairing screen** closes automatically on success; clear status/error line with a spinner.

### Fixed
- **A wrong pairing code led to a timeout / cryptic error**: The host discarded the OTP but didn't generate a new one; the client ran into a timeout because the `pair_error` frame was lost when the connection was closed immediately.
  - **macOS**: on a wrong code, a **new OTP** is now generated automatically right away (window stays open, friendly hint, countdown reset); `pair_ok`/`pair_error` are closed only **after confirmed send** (no more discarded frames), including generating a new code on expiry.
  - **iOS**: reacts to `pair_error` immediately (clear "Wrong code" hint, field reset, reconnect against the new code) with a grace period so the error always beats the connection drop; a real timeout remains only as the last resort.

## [0.7.0] – 2026-08-25

### Changed
- **Rebrand to "KeystrokeQR"**: iOS app → **KeystrokeQR**, macOS menu bar app → **KeystrokeQR Host**. New bundle IDs: `de.timehrenfried.keystrokeqr` (app), `.widgets` (widget), `.host` (Mac). Bonjour service type `_qr-keyboard._tcp` → `_keystrokeqr._tcp`, URL scheme `qrkeyboard://` → `keystrokeqr://`, keychain services adjusted. GitHub repo + local folder → `keystrokeqr`. Authoritative naming spec: [docs/BRANDING.md](docs/BRANDING.md).
  - **Breaking**: because of the changed service types/bundle IDs, existing v0.6.x pairings must be redone once and both apps must be updated together.

### Added
- **Internationalization (i18n)**: English as the base language, German in addition — both apps fully localized (iOS via string catalogs `Localizable.xcstrings`/`InfoPlist.xcstrings`, 103 keys; macOS via `en.lproj`/`de.lproj`).
- **iOS – first-run onboarding**: four-page intro flow (welcome / how it works / permissions with contextual camera prompt / pairing), shown once on first launch, reopenable from Help.
- **macOS – styled DMG installer**: `make dmg` produces `KeystrokeQR-Host.dmg` (window background image, app + /Applications symlink); the release workflow uploads `KeystrokeQR-Host-macOS.dmg` as an asset (replacing the ZIP).
- **New app icons** (iOS + macOS) in the KeystrokeQR motif (QR viewfinder + keystroke/key accent, yellow scan line), stylistically consistent across both platforms.

## [0.6.1] – 2026-08-25

### Fixed
- **iOS – "Mac app outdated" despite a v0.6.0 host**: `NWBrowser` does not reliably deliver the Bonjour TXT record in browse results (often `.none`), so the client wrongly classified every Mac as v1 and suppressed the pairing screen. A host is now only considered outdated if it **explicitly** announces `v=1`; a missing record or `v=2` → treated as v2 (the version is checked conclusively during the handshake). The pairing dialog now appears correctly.

## [0.6.0] – 2026-08-25

### Added
- **End-to-end encryption + device pairing (protocol v2)**: Every connection is now encrypted and mutually authenticated. An iPhone has to be paired once — the Mac shows a 6-digit OTP (90 s) in the menu under "Pair device…", which the iPhone enters once. Under the hood: Curve25519 key exchange with OTP-HMAC confirmation → long-lived PSK (in both keychains, never sent over the network), a fresh HKDF session key per session, all scan/ack frames as ChaChaPoly AEAD with replay protection (CryptoKit). Specification: [docs/PROTOCOL-v2.md](docs/PROTOCOL-v2.md).
- **Mac – device management**: the menu lists paired iPhones (with pairing date) plus "Remove" (revokes the PSK immediately, terminates the running session); status "N paired · M connected".
- **iOS – pairing UI**: setup/pairing screen (choose Mac, enter OTP) and "Manage paired Macs"; notice banner when a discovered Mac is still running v1 (< 0.6.0).

### Changed
- **Breaking**: Protocol v2 replaces v1 (Bonjour TXT `v=2`); a v2 host accepts only v2 clients and vice versa. Update the Mac and iOS apps together.

### Security
- Closes the open SECURITY.md findings **LAN keystroke injection**, **plaintext sniffing**, and **host spoofing** (only paired, PSK-authenticated devices get through). The residual risk of OTP entropy (~20 bits, one attempt per 90-second window) is documented.

## [0.5.1] – 2026-08-25

### Fixed
- **iOS – overlay edge spacing, final fix**: The control-bar row overflowed the screen width because of the non-shrinkable toggles (`.fixedSize()`), pulling the shutter capsule and bar flush to the edge — toggles are now chips with scalable/truncatable labels, and the row spacing is reduced. Verified pixel-perfect in the simulator (16 pt side margins, 12 pt above the home indicator).
- Reverted an accidental folder rename of `ios/Shared/` (the app had typed a scan payload into a focused Xcode rename field — a real-world demonstration of the injection risk described in SECURITY.md and of the pairing plan).

### Added
- `docs/PLAN-SECURITY-DISTRIBUTION.md`: plan for TLS-PSK encryption + one-time OTP pairing, plus CI/CD distribution (App Store/TestFlight + notarized DMG). Planning only, no implementation.

## [0.5.0] – 2026-08-25

### Added
- **iOS – code outlines**: yellow, smoothly tracking frames around all currently detected codes (CAShapeLayer on the preview, perspective-correct corners via `transformedMetadataObject`, fade-out when leaving the frame) — like the system QR scanner.
- **iOS – Help "About" section**: app version/build shown dynamically, © 2026 Tim Ehrenfried, contact mail@tim-ehrenfried.de, GitHub link.
- **App icons** for iOS (asset catalog, 1024-pt single size) and macOS (AppIcon.icns in the bundle): dark gradient, white QR viewfinder motif, yellow scan line.
- **GitHub infrastructure**: CI workflow (macOS host build + iOS simulator build) and release workflow (tag `v*` → `QR-Keyboard-Host-macOS.zip` as a GitHub release), `SECURITY.md` (threat model, recommendations, responsible disclosure), `docs/INSTALL.md` (end-user installation including Gatekeeper).

### Fixed
- **iOS – layout**: overlays (status, shutter, control bar) sat flush against the screen edges; now consistent 16 pt margins, the control bar is a rounded card, and the safe area/home indicator are respected.

### Security
- **macOS – DoS protection**: WebSocket frames capped at 64 KiB and `text` at 8192 UTF-16 code units; exceeding the limit → new ack `payload_too_large` instead of minutes of "typing it all out" (PROTOCOL.md updated).

## [0.4.0] – 2026-08-25

### Added
- **iOS – send-once**: Each code is sent automatically only once per app session. If an already-sent code is detected again, a yellow "Send again" trigger appears instead (only while the code is in frame, fades out after 2.5 s) — only pressing it sends again. Subtle repeat haptic once per sighting, framerate-debounced. Plus a "Clear history" button (with confirmation); the sent set is intentionally not persisted and clears on app restart.

## [0.3.0] – 2026-08-25

### Added
- **iOS – camera**: virtual camera with automatic lens/macro switching (Triple → DualWide → Dual → wide-angle fallback), correct initial zoom (no ultra-wide start), continuous autofocus with near-range restriction + auto exposure + subject-area reset, **tap-to-focus** with a focus frame, and **pinch-to-zoom** (up to 10x).
- **iOS – dark launch/loading state**: black launch screen (UILaunchScreen + asset color), black "Starting camera…" overlay until the session is running, dark camera-denied screen.

### Fixed
- **iOS 18 Lock Screen control opened nothing**: The control intent is executed by the system in the app process, but only existed in the widget extension → `StartScanIntent` now lives in `Shared/` with membership in both the app **and** the extension; the error-prone `OpenURLIntent` variant (iOS 18.0 bug) was removed. ControlWidget, Action Button, Shortcuts, and Siri all run through the same intent.

## [0.2.0] – 2026-08-25

### Added
- **iOS – quick start from the Lock Screen**: widget extension `QRKeyboardScannerWidgets` with a Lock Screen widget (accessoryCircular/-Rectangular, systemSmall) via deep link `qrkeyboard://scan`; iOS 18 ControlWidget for Lock Screen quick controls and Control Center; App Intent "Scan QR Code" + App Shortcuts (Siri, Spotlight, Shortcuts app, Action Button); URL scheme `qrkeyboard` with a robust `.onOpenURL` handler including cooldown reset.
- **Docs**: `docs/SETUP.md` — step by step from the Apple Developer account to a running system (signing, Developer Mode, permissions, Lock Screen setup, troubleshooting); in-app help and READMEs extended accordingly.

### Changed
- **macOS – Makefile**: new variable `SIGN_IDENTITY` (default ad-hoc) for a stable signature with a developer certificate; signing with Hardened Runtime (`--options runtime`).

## [0.1.0] – 2026-08-25

### Added
- **macOS host** (`macos/`): menu bar app with a local WebSocket server (Network.framework, port 8080 with fallback), Bonjour advertising `_qr-keyboard._tcp`, key injection via CGEvent (Unicode-safe, layout-independent), optional Tab/Enter after the text, Accessibility status display including a direct link to System Settings, Makefile build to a `.app` bundle.
- **iOS scanner** (`ios/`): SwiftUI app with a full-screen camera viewfinder (AVFoundation, QR + common barcode types), automatic Mac discovery via Bonjour (no IP entry), WebSocket delivery, haptic feedback, 1 s scan cooldown, Auto-Enter/Auto-Tab toggles (persistent), automatic reconnect, and in-app help.
- **Protocol specification** `docs/PROTOCOL.md` (Bonjour + WebSocket + JSON, ack with error codes).
- Documentation: root README, component READMEs with Accessibility guide, MIT license.
