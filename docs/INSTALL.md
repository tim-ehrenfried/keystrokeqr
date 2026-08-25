# Installation for End Users (no Xcode)

This guide is for users who simply want to **download and use** the ready-made
macOS app. If you want to build it yourself (or get the iOS app onto your
iPhone), everything is in [SETUP.md](SETUP.md).

## 1. Download the macOS app

1. Get the latest version:
   **[github.com/tim-ehrenfried/keystrokeqr/releases/latest](https://github.com/tim-ehrenfried/keystrokeqr/releases/latest)**
   → under *Assets*, click the file **`KeystrokeQR-Host-macOS.dmg`**.
2. Double-click the downloaded **`KeystrokeQR-Host-macOS.dmg`** → a window
   opens with **"KeystrokeQR Host.app"** and an **Applications** folder next to it.
3. Drag the app onto the **Applications** folder in the same window.
   Then eject the DMG (click ⏏ next to the volume in Finder).

Requirement: **macOS 13 (Ventura) or newer**.

## 2. Gatekeeper: "App can't be opened"

The app is **ad-hoc signed and not notarized** (an open-source project without
a paid Apple Developer certificate). macOS therefore blocks it with a warning
on first launch. Two ways to approve it once:

**Option A — right-click:**

1. In the *Applications* folder, **right-click** (or ctrl-click)
   "KeystrokeQR Host" → **Open**.
2. Confirm **Open** again in the dialog.
   (From macOS 15 Sequoia, possibly also: *System Settings → Privacy &
   Security* → at the very bottom, next to the blocked app, **"Open Anyway"**.)

**Option B — Terminal (remove the quarantine attribute):**

```bash
xattr -d com.apple.quarantine "/Applications/KeystrokeQR Host.app"
```

After that, the app launches normally with a double-click.

> If you'd rather not trust the downloaded binary, you can build the app
> yourself from source in a few minutes: `cd macos && make app`
> (see [../macos/README.md](../macos/README.md)).

## 3. Grant Accessibility access (required)

For the app to be allowed to **type** the scanned text, it needs the macOS
**Accessibility** permission:

1. Launch the app → a QR icon appears in the menu bar.
2. *System Settings → Privacy & Security → Accessibility* →
   enable the toggle for **"KeystrokeQR Host"**.
   (If the entry is missing: click **+** at the bottom → select
   "KeystrokeQR Host.app" in the Applications folder. The app's menu item
   **"Open Accessibility…"** takes you straight there.)
3. Quit the app once and relaunch it — the menu then shows
   **"Accessibility: ✓ granted"**.

Additionally, if macOS asks or the firewall is active:

- Allow **local network** access for the app (prompt from macOS 15).
- *System Settings → Network → Firewall → Options* → allow incoming
  connections for "KeystrokeQR Host".

Detailed steps with troubleshooting: [SETUP.md](SETUP.md).

## 4. Install the iOS app (scanner)

The iPhone app is **currently not on the App Store**. It is installed onto the
iPhone with Xcode and your own (even free) Apple Developer account —
the step-by-step guide is in [SETUP.md](SETUP.md), section
"Getting the iOS app onto your iPhone".

## 5. Get going

1. Put the Mac and iPhone on the **same Wi-Fi**.
2. Open the iOS app → it finds the Mac automatically.
3. **Pair once:** on the Mac choose "Pair device…" in the menu bar app and
   enter the 6-digit code on the iPhone. Afterwards the app reconnects
   automatically ("Connected to …").
4. On the Mac, put the cursor in a text field, scan a code → the text is
   typed instantly.

**Note:** The connection is end-to-end encrypted and only works between
devices you explicitly paired with a one-time code. Still, prefer trusted
networks and quit the app when you're not using it.
Details: [SECURITY.md](../SECURITY.md).
