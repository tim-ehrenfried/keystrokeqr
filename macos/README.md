# KeystrokeQR Host (macOS)

Menu bar app of the open-source system **KeystrokeQR**: receives QR scans from
the iPhone (via WebSocket on the local network, Bonjour discovery) and types the
scanned text as real keystrokes into the currently focused window —
optionally followed by Tab and/or Enter.

Protocol: see [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md)
(Bonjour `_keystrokeqr._tcp`, port 8080 with fallback to a free port,
JSON messages over WebSocket). Since v0.6.0 the connection is paired
(one-time OTP pairing) and end-to-end encrypted — see
[`../SECURITY.md`](../SECURITY.md). Names/IDs are authoritatively defined in
[`../docs/BRANDING.md`](../docs/BRANDING.md).

- **Bundle ID:** `de.timehrenfried.keystrokeqr.host`
- **Bonjour service type:** `_keystrokeqr._tcp` (must match the iOS client exactly)
- **Version:** 0.16.0

## Requirements

- macOS 13 (Ventura) or newer
- Xcode or the Swift toolchain (Swift 5.9+; tested with Swift 6.3)
- For icon/DMG generation: ImageMagick 7 (`magick`) plus `sips`/`iconutil`
  (part of macOS)

## Building

```sh
cd macos
make app
```

This produces the app bundle **`dist/KeystrokeQR Host.app`** (release build,
ad-hoc signed) including localizations (`Contents/Resources/en.lproj` +
`de.lproj`). The bundle matters so that macOS can cleanly attribute the
Accessibility permission **per app**.

Additional targets:

| Target       | Effect                                                     |
| ------------ | ---------------------------------------------------------- |
| `make build` | build only the release binary                              |
| `make icon`  | regenerate the app icon `Support/AppIcon.icns` (ImageMagick) |
| `make app`   | create the app bundle under `dist/`                        |
| `make dmg`   | build the styled `dist/KeystrokeQR-Host.dmg`               |
| `make run`   | build the bundle and launch it                             |
| `make clean` | remove build artifacts, `dist/`, and the background image  |

To sign with an Apple Developer account instead of ad-hoc:

```sh
make app SIGN_IDENTITY="Developer ID Application: Tim Ehrenfried (TEAMID)"
```

(list available identities with `security find-identity -v -p codesigning`)

## Official vs. community builds

The repo builds **neutral by default**: personal contact and infrastructure
references (contact email, landing page, iPhone-app link/QR) are **not**
compiled in. They live behind the compile-time flag `OFFICIAL_BUILD` in
`Sources/QRKeyboardHost/BrandingConfig.swift`:

| Variant             | How to build                        | Behavior                                                                 |
| ------------------- | ----------------------------------- | ------------------------------------------------------------------------ |
| Community (default) | `make build` / `make app` / `make dmg` | `BrandingConfig` values are `nil`: no "Get the iPhone app" QR card, no email button; the About page shows "Community build — source & issues on GitHub". |
| Official (our CI/signing) | `make build OFFICIAL=1` (same for `app`/`dmg`) | Builds with `swift build -c release -Xswiftc -DOFFICIAL_BUILD`; contact email, landing page (`keystrokeqr.tim-ehrenfried.de`), and the iPhone-app QR (`…/ios`) are compiled in. |

The **GitHub repository link is intentionally not gated** — source & issues
apply to both variants. The onboarding assistant and the Help subpage render
the iPhone-app QR code natively via CoreImage (`CIQRCodeGenerator`, sharply
scaled, dark modules on a white tile) **only in official builds**.

## DMG installer (`make dmg`)

`make dmg` produces a styled disk image **`dist/KeystrokeQR-Host.dmg`** with a
background image (dark, "KeystrokeQR Host" + an arrow "→ drag to Applications"),
the app icon on the left, and an **/Applications symlink** on the right.

- If `create-dmg` (Homebrew: `brew install create-dmg`) is installed, it is
  preferred and sets the window size + icon positions directly.
- Otherwise the `hdiutil` fallback kicks in. It places the app, the
  `/Applications` symlink, and the background image (`.background/background.png`)
  into the volume and **attempts** the fine styling (icon positions, window)
  via Finder AppleScript.

> **Limitation (headless/CI):** The Finder AppleScript styling requires a
> GUI/Finder session. If `make dmg` runs without one (e.g. in GitHub Actions),
> the styling is skipped — the DMG is still fully functional (app +
> `/Applications` symlink + background image), just without preset icon
> coordinates. For a pixel-perfect styled DMG, run `make dmg` locally or with
> `create-dmg` installed.

The DMG is signed ad-hoc or with `SIGN_IDENTITY` (notarization is not part of
this target).

## Internationalization (i18n)

All user-visible host strings (menu items including typing speed, status lines,
the pairing window including countdown/hints, and the onboarding/welcome
window) are localized. **The base/development language is English (`en`)**,
with German (`de`) in addition.

- Sources: `Support/en.lproj/Localizable.strings` and
  `Support/de.lproj/Localizable.strings` (plus `InfoPlist.strings` for the
  permission dialogs). `make app` copies them to
  `Contents/Resources/<lang>.lproj/`.
- In code, access goes through the helper function `L(_:)`
  (`NSLocalizedString`, table `Localizable`) — see
  `Sources/QRKeyboardHost/Localization.swift`.
- The displayed language follows the user's system setting.

## Launching

```sh
make run
# or:
open "dist/KeystrokeQR Host.app"
```

The app appears as a QR icon in the menu bar (no Dock icon). Since v0.9.0 the
menu is **slim** and mainly serves as a status glance:

- **Pairing/connection status** ("No device paired" / "N paired · M connected")
- **Port and Bonjour service name** (the Mac's hostname)
- **Accessibility status** (✓/✗) — see at a glance whether everything is ready
- **Autostart status** ("Start at login: ✓/✗")
- **"Open KeystrokeQR…"** — opens the central control panel (see below)
- **Quit**

Optionally, the app can be added to **Login Items**
(System Settings → General → Login Items) so it starts automatically.

## Control panel (KeystrokeQR panel)

Since **v0.9.0**, all functionality is bundled in a styled window in the dark
KeystrokeQR look (instead of many menu items). Open it via the menu item
**"Open KeystrokeQR…"**. The panel runs as a normal, focusable window while the
app remains a pure menu bar app (`.accessory`).

Since **v0.10.0** it is **a single window** with internal navigation: "Help"
and "About" slide in as subpages within the same frame (no scrolling — the
window opens at exactly the content size for each page and animates its size
while navigating). Top left is a **back button** (only on the subpages), top
right at the same height a subtle gray **"Introduction"** button.

Since **v0.12.0** the home view is in **landscape**: two card columns side by
side (noticeably wider than tall, ~786 pt wide) instead of one tall, narrow
column. Left: Connection, Accessibility, Confirm before typing.
Right: Paired devices, Typing speed, Start at login. The header and footer
(Help/About) span both columns. The "as large as needed, no scrolling"
principle remains; Help/About stay narrower (single-column).
Sections of the home view:

- **Connection** — Bonjour service name, port, and "N paired · M connected".
- **Accessibility** — a large green ✓ "Enabled" or red ✗ "Not enabled" with a
  short explanation and an "Open Accessibility…" button. The status is
  **live**: while the panel is open (and active), it polls
  `AXIsProcessTrusted()` every ~1.5 s and additionally refreshes immediately
  when the window gains focus — so after granting the permission the ✓ appears
  without restarting the app.
- **Paired devices** — a list (name + pairing date) with "Rename" and
  "Remove" per device and "Pair device…" (opens the existing pairing window).
  "Remove" deletes the shared key (PSK) from the keychain **and** immediately
  disconnects any running session of that device so the client notices the
  disconnect and can enter re-pairing
  (docs/PROTOCOL-v2.md, "Device management"). If nothing is paired yet, the
  card shows an empty state ("No device paired yet — choose 'Pair device…'.").
- **Typing speed** — Fast / Normal / Slow as a segmented control, effective
  immediately (see below).
- **Confirm before typing** — toggle (default OFF); see below.
- **Start at login** — toggle with live registration status (see below).
- Entry points to the **Help** and **About** subpages (the "Introduction" lives
  as the gray button at the top right).

All panel controls carry **accessibility labels/roles** for VoiceOver
(toggles, segmented control, device rows including "Rename"/"Remove", the
Accessibility status symbol).

## Help & About (subpages)

- **Help** (button in the home view) slides in a subpage with a quick guide
  (background operation, pairing, Accessibility, typing speed for long text),
  troubleshooting (iPhone can't find the Mac → same Wi-Fi/firewall/VPN;
  nothing gets typed → Accessibility), and links to the
  [GitHub repo](https://github.com/tim-ehrenfried/keystrokeqr) and the
  documentation (as buttons with icons). Bilingual (en/de).
- **About** shows the app name "KeystrokeQR Host", version/build **dynamically
  from the bundle**, "© 2026 Tim Ehrenfried", the MIT license, and the links —
  GitHub, website + email (official builds only, see
  "Official vs. community builds"), and documentation — as **buttons with
  SF Symbols** (like in the iOS app), in the dark KeystrokeQR style
  (no NSAboutPanel default). Community builds show
  "Community build — source & issues on GitHub" instead of the personal
  contact references.

## Welcome / onboarding (first launch)

On the **very first launch**, the app walks through a small setup assistant
once (dark KeystrokeQR look). Overall flow:

**Welcome → How it works → Accessibility (checked live) → "Pair device" →
"Success! Get started" → control panel.**

- The **Accessibility status is checked live** — analogous to the control
  panel: while the window is active, a timer (~1.2 s) polls
  `AXIsProcessTrusted()` and additionally refreshes **immediately** when the
  window gains focus (the user may just be coming back from System Settings).
  Not granted → red hint + "Open Accessibility…" button; **granted → green
  success state "Accessibility enabled ✓"**, and the button disappears.
- The **final action is "Pair device"** (opens the existing pairing flow) — as
  long as Accessibility is **not** granted, it is **disabled** and a hint
  explains why. There is no generic "Get started" finish button anymore.
- **After successful pairing**, the assistant shows a short success step
  "Successfully paired!" with **"Get started"** — this closes the onboarding
  and **jumps to the control panel**. (Pairing outside the onboarding keeps
  the existing auto-close of the pairing window — no jump.)

Whether onboarding has been completed is stored in UserDefaults
(`didCompleteHostOnboarding`). It can be reopened at any time via the gray
**"Introduction"** button at the top right of the KeystrokeQR window.

## Typing speed

The **"Typing Speed"** submenu sets how quickly received text is typed
(persisted in UserDefaults, the current level shown with a checkmark):

| Level    | Behavior                                                             |
| -------- | ------------------------------------------------------------------- |
| Fast     | large chunks, very short pause — quick                              |
| Normal   | default (matches the previous behavior)                             |
| Slow     | small chunks, noticeably longer pause — robust for sluggish/remote  |
|          | target fields (remote sessions), so nothing gets stuck or dropped   |
|          | with lots of text                                                   |

The change takes effect immediately for the next scan.

## "✓ Typed" HUD

After every **successful** keystroke injection, the app briefly (~0.9 s) shows
a subtle, self-dismissing "✓ Typed" HUD. Since **v0.12.0** it appears
**bottom-center** — about 20% of the visible screen height above the bottom
edge (`NSScreen.main.visibleFrame`), no longer at the top. The look is modern
and clean, matching the dark KeystrokeQR design: a **solid dark, rounded
card** with a subtle border and soft shadow (no more washed-out
blur/`NSVisualEffectView`), crisp light text, and a checkmark in the
**brand yellow (#FFD60A)** as a rendered SF Symbol. Soft fade in/out.

It serves purely as feedback and is built so it **never steals keyboard
focus** (otherwise input into the target window would break): a borderless,
**non-activating** `NSPanel` (`.nonactivatingPanel`, `isFloatingPanel`,
`level = .statusBar`, `ignoresMouseEvents`, `hidesOnDeactivate = false`) that
is shown exclusively via `orderFrontRegardless()` — never
`makeKey`/`activate`. For rapid consecutive scans, the same panel is reused
and only the fade-out timer is reset (no stacking).

## Confirm before typing

In the control panel, the **"Confirm before typing"** mode can be enabled
(default **OFF**; persisted in UserDefaults). When on, an incoming scan is
**not typed immediately**: instead, a non-activating panel appears with a
truncated **preview** of the text (plus character count and whether Tab/Enter
follows) and the buttons **"Type"** / **"Discard"**.

So the text reliably lands in the original target field, the app remembers the
foreign app that was focused **before** showing the panel
(`NSWorkspace.shared.frontmostApplication`). On "Type", that app is
reactivated first, followed by a short wait, and **then** typing happens;
"Discard" types nothing. The normal path (mode OFF) is unchanged — immediate
typing. Multiple scans arriving in quick succession are serialized (one panel
after another).

## Renaming a device

In the device list, each row offers a **"Rename"** next to "Remove"
(a small dialog with a pre-filled name field). The new name is persisted in
the keychain device entry (`CryptoManager.renameDevice(_:to:)`); an empty
name is not allowed. PSK, public key, and pairing date remain untouched.

## Start at login

The **"Start at login"** toggle registers the app as a login item
(`SMAppService.mainApp`, macOS 13+). The toggle shows the **actual
registration status** and handles errors gracefully; if macOS requires
approval, a hint points to **System Settings › General › Login Items**.
The menu bar entry mirrors the state ("Start at login: ✓/✗").

> **Note:** `SMAppService` works reliably only from an **installed**
> `.app` (e.g. in `/Applications`). From a bare SPM binary without a bundle,
> registration may fail — the logic still reads the status correctly and
> works in the shipped app.

## Tests (`swift test`)

The security/protocol-critical core logic is covered with XCTest
(test target `QRKeyboardHostTests` under `Tests/QRKeyboardHostTests/`,
`swift test`):

- **HKDF derivations** (`CryptoCore`): PSK/confirm/session key with the exact
  salt/info strings from docs/PROTOCOL-v2.md — determinism, agreement on both
  sides, different inputs ⇒ different keys.
- **Pairing HMAC**: a correct OTP verifies, a wrong one does not;
  constant-time comparison (`HMAC.isValidAuthenticationCode`).
- **ChaChaPoly frame** (`SecureFrame`): seal→open round trip, nonce =
  direction prefix ‖ big-endian seq, replay/monotonicity logic, tampered
  ciphertext/tag fails.
- **Messages** (Codable): scan/ack/pair_*/session_*/enc — exact field names.
- **Payload limit**: 8192 UTF-16 (`ScanServer.isTextWithinLimit`), including
  surrogate-pair counting.
- **TypingSpeed mapping**: chunk size/pause per level.

To make the logic testable without networking/UI, the pure crypto derivations
were extracted into `CryptoCore` and the length-limit logic into a static
function (no behavior change — `CryptoManager`/`ScanServer` delegate to them).

## Granting the Accessibility permission (required!)

For the app to be allowed to "type" keystrokes into other programs, it needs
the macOS **Accessibility** permission. Without it, the app answers scans
with the error `accessibility_denied`.

Step by step:

1. **Launch the app** (`make run`). On the first scan without the permission,
   macOS automatically shows a prompt — alternatively, go directly via the
   app's menu: **"Open Accessibility…"**.
2. **System Settings → Privacy & Security → Accessibility** opens.
3. If **"KeystrokeQR Host"** is already in the list: **enable the toggle**.
4. If the app is not in the list yet: click **"+"** at the bottom, navigate
   to the `macos/dist/` folder, select **"KeystrokeQR Host.app"**, then
   enable the toggle.
5. Confirm with the administrator password if asked.
6. The Accessibility status is detected **live**: in the control panel
   (**"Open KeystrokeQR…"**) the display switches to the green ✓ "Enabled"
   within ~1–2 s after granting — no app restart needed. The menu bar also
   shows **"Accessibility: ✓ granted"** the next time it's opened.

> **Note after updates:** If the app is rebuilt (new binary/signature),
> macOS may drop the permission. In that case, remove the entry in
> **Privacy & Security → Accessibility** (minus button) and **re-add** the
> app as described above, or re-enable the toggle.

> **Note on the rebrand (v0.7.0):** Bundle ID, keychain service, and
> Bonjour service type have changed. Existing pairings from v0.6.x must be
> redone **once** (see [`../docs/BRANDING.md`](../docs/BRANDING.md)).

## Local network

From macOS 15 (Sequoia), macOS may additionally ask for **local network**
access — allow this too, otherwise the iPhone cannot find the Mac via
Bonjour.

## How it works (in short)

- WebSocket server via `Network.framework` (`NWListener` + WebSocket options,
  `autoReplyPing`), fixed port **8080**, automatically a free port if it's
  taken (the iOS client always uses the port resolved via Bonjour).
- Bonjour advertising as `_keystrokeqr._tcp` with TXT record `v=2`.
- Every connection goes through either OTP pairing (only while the
  "Pair device…" window is open) or the session handshake for already-paired
  devices; after that, exclusively ChaChaPoly-encrypted frames
  (Curve25519 + HKDF-SHA256, identity + PSKs in the keychain, service
  `de.timehrenfried.keystrokeqr.host`). Details:
  [`../docs/PROTOCOL-v2.md`](../docs/PROTOCOL-v2.md).
- Multiple iPhones can be connected simultaneously; scans are typed strictly
  sequentially (order: text → Tab → Enter).
- Text injection is Unicode-based via `CGEvent` and therefore independent of
  the active keyboard layout (including emoji and special characters).
