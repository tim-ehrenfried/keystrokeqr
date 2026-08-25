# Step by Step: From the Apple Developer Account to a Running System

This guide walks through everything once: activate the account → iOS app onto the iPhone → set up the Mac app → Lock Screen quick start.

## 0. Apple Developer account (in progress)

1. After purchase, activation usually takes **a few hours up to 48 h**. You'll get a confirmation email "Welcome to the Apple Developer Program".
2. Check the status: [developer.apple.com/account](https://developer.apple.com/account) → at the top it must say "Apple Developer Program" (no longer "Pending").
3. **Important:** Until activation you can already deploy everything to the iPhone with the *free* Personal Team — the app then runs for only 7 days and must be reinstalled. With an activated account, provisioning is valid for **1 year**.

## 1. Connect Xcode to the account

1. Open Xcode → menu **Xcode → Settings… → Accounts**.
2. Bottom left **+** → **Apple ID** → sign in with the Apple ID of the developer account.
3. After activation, your team appears on the right with the suffix **"(Company/Individual)"** instead of "(Personal Team)".

## 2. Getting the iOS app onto your iPhone

1. Open the project:
   ```bash
   open /Users/timehrenfried/DEV/TOOLS/keystrokeqr/ios/QRKeyboardScanner.xcodeproj
   ```
2. In the navigator, click the project **QRKeyboardScanner** → target **QRKeyboardScanner** → tab **Signing & Capabilities**:
   - ✅ *Automatically manage signing*
   - **Team**: choose your developer team.
   - If Xcode reports a bundle ID collision, tweak the ID slightly (e.g. `de.timehrenfried.keystrokeqr2`).
   - Do the same **for the widget target `QRKeyboardScannerWidgets`** (same team; the extension's bundle ID must start with the app ID).
3. Connect the iPhone to the Mac via **USB cable** (first time), confirm **"Trust This Computer"** on the iPhone.
4. Enable **Developer Mode** on the iPhone: *Settings → Privacy & Security → Developer Mode* → turn on → restart → confirm after the restart. (The toggle only appears once the iPhone has been connected to Xcode.)
5. In Xcode's device bar at the top, select your iPhone as the destination → **▶ Run** (⌘R). Xcode installs and launches the app.
   - After that it also works wirelessly: as long as iPhone + Mac are on the same Wi-Fi, the device keeps showing up in Xcode.
6. On first launch on the iPhone, **allow** two dialogs:
   - **Camera** (for the scanner)
   - **Local network** (for the Bonjour discovery of the Mac — without it the app can't find the Mac!)
   - If accidentally denied: *Settings → Apps → KeystrokeQR* → enable both.

## 3. Build, launch, and unlock the Mac app

1. Build and launch:
   ```bash
   cd /Users/timehrenfried/DEV/TOOLS/keystrokeqr/macos && make run
   ```
   (With an active dev account you can optionally sign with a stable identity, so the permission survives rebuilds:
   `make app SIGN_IDENTITY="Apple Development: <your name> (TEAMID)"` — list identities with `security find-identity -v -p codesigning`.)
2. The QR icon appears in the menu bar. Open the menu → check the Accessibility status.
3. **Grant Accessibility access** (required for typing):
   *System Settings → Privacy & Security → Accessibility* → enable the toggle for **"KeystrokeQR Host"** (if the entry is missing: click **+** at the bottom → select `macos/dist/KeystrokeQR Host.app`).
4. If macOS (15+) asks for **"Local Network"** access for the app → allow it.
5. Firewall active? *System Settings → Network → Firewall → Options* → allow incoming connections for "KeystrokeQR Host".

## 4. One-time pairing (mandatory since v0.6.0)

Since v0.6.0 the connection is end-to-end encrypted and **paired** —
an iPhone must be introduced to the Mac once before it can trigger
keystrokes (details: [PROTOCOL-v2.md](PROTOCOL-v2.md), security assessment:
[../SECURITY.md](../SECURITY.md)).

1. Mac and iPhone on the **same Wi-Fi** (WARP/VPN on the Mac can interfere with mDNS — when in doubt, disable it briefly).
2. On the Mac, open the QR icon in the menu bar → **"Pair device…"**. A
   window with a **6-digit code** appears (valid for 90 seconds).
3. Open the app on the iPhone. When the Mac is found for the first time, the
   pairing screen appears automatically: type in the code → **"Pair"**.
4. After successful pairing, the app automatically reconnects — the status
   capsule switches to **"Connected to \<Mac name\>"**; the Mac menu shows
   "1 paired · 1 connected" and lists the iPhone among the paired devices
   (with a "Remove" option).
5. Pairing is **one-time** — on future launches, the app connects
   automatically with the stored key, no new code needed.

## 5. First end-to-end test

1. On the Mac, put the cursor in a text field (TextEdit is enough), scan a QR code on the iPhone → the text appears at the cursor instantly. Use the **Auto-Enter/Auto-Tab** toggles as needed.

## 6. Quick start from the Lock Screen

The app ships a Lock Screen widget, an iOS 18 control, and a shortcut:

- **Lock Screen widget:** press and hold the Lock Screen → **Customize** → Lock Screen → tap the widget area below the clock → **KeystrokeQR** → add the widget. Tapping it launches the scanner directly.
- **iOS 18 – replace the bottom quick controls:** while customizing the Lock Screen, tap the flashlight/camera button (−), then **+** → choose the **"Scan QR"** control. It can also be placed in **Control Center** (open Control Center → + at the top left → add control).
- **Action Button (iPhone 15 Pro / 16):** *Settings → Action Button* → **Shortcut** → choose "Scan QR Code".
- **Siri/Spotlight:** "Scan QR Code" works directly as a Siri phrase and in the Shortcuts app as a building block for your own automations.

## Troubleshooting

| Problem | Solution |
|---|---|
| iPhone can't find the Mac | Same Wi-Fi? Local-network permission on **both** devices? VPN/WARP off on the Mac? Firewall exception? |
| Mac doesn't type | Accessibility permission missing/lapsed → remove the entry in System Settings and grant it again (happens after rebuilds with an ad-hoc signature). |
| "Untrusted Developer" on the iPhone | Only with the free Personal Team: *Settings → General → VPN & Device Management* → trust the developer. |
| App disappears after 7 days | Free team in use — after account activation, choose the right team in Xcode and reinstall. |
| "Please update the Mac app" | The discovered Mac is still running v1 (before 0.6.0) — rebuild/reinstall the Mac app. |
| Pairing fails with "Wrong code" | The code is valid for only 90 s **and a single attempt** — on the Mac, generate a new code via the "Pair device…" menu. |
| Still "not_paired" after pairing | The device was removed on the Mac in the meantime (menu → device → "Remove") — the app then automatically offers re-pairing. |
