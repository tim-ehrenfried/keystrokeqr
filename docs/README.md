# KeystrokeQR – Documentation

Overview of all documents. Scan a QR or barcode with your iPhone — the text is
typed instantly at the cursor position on your Mac. Entirely local on your Wi-Fi, encrypted.

← Back to the [project overview](../README.md)

## For users

| Document | What it covers |
|---|---|
| **[INSTALL.md](INSTALL.md)** | Install the ready-made Mac app from the release DMG (no Xcode), Gatekeeper notes, granting Accessibility access. **Start here if you just want to use KeystrokeQR.** |
| **[SETUP.md](SETUP.md)** | The full path for developers: Apple Developer account, iOS app onto the iPhone, building the Mac app, **one-time pairing**, first test, Lock Screen quick start, troubleshooting. |

## Usage in a nutshell

1. **Mac:** launch KeystrokeQR Host (menu bar) and grant the Accessibility permission once.
2. **iPhone:** open KeystrokeQR → the Mac is found automatically.
3. **Pair:** on the Mac choose "Pair device…", enter the 6-digit code on the iPhone (first time only).
4. **Scan:** put the cursor in the target field on the Mac, scan a QR/barcode → the text is typed (optionally + Tab/Enter).

Everything else is explained in the **in-app help** of both apps.

## Technical documentation

| Document | What it covers |
|---|---|
| **[PROTOCOL-v2.md](PROTOCOL-v2.md)** | Current network protocol: Bonjour discovery, OTP pairing (Curve25519), encrypted session (HKDF + ChaChaPoly), error handling. **Authoritative for host & client.** |
| **[PROTOCOL.md](PROTOCOL.md)** | Original, unencrypted v1 protocol (historical, superseded by v2). |
| **[BRANDING.md](BRANDING.md)** | Authoritative names, bundle IDs, service types, i18n basics. |
| **[SECURITY.md](../SECURITY.md)** | Threat model, security decisions, recommendations, responsible disclosure. |
| **[RELEASE-PHASE.md](RELEASE-PHASE.md)** | The final release playbook: signing, App Store/TestFlight, notarized DMG, going public. |
| **[PLAN-SECURITY-DISTRIBUTION.md](PLAN-SECURITY-DISTRIBUTION.md)** | Earlier roadmap (Part A security done; distribution superseded by RELEASE-PHASE.md). |

## Repository structure

- [`ios/`](../ios/) — iOS scanner app (SwiftUI, AVFoundation), see [ios/README.md](../ios/README.md)
- [`macos/`](../macos/) — macOS menu bar host (Swift, CGEvent), see [macos/README.md](../macos/README.md)
- [`docs/`](.) — this documentation
- [`CHANGELOG.md`](../CHANGELOG.md) — version history (SemVer)
