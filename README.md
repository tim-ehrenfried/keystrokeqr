# KeystrokeQR

[![CI](https://github.com/tim-ehrenfried/keystrokeqr/actions/workflows/ci.yml/badge.svg)](https://github.com/tim-ehrenfried/keystrokeqr/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tim-ehrenfried/keystrokeqr)](https://github.com/tim-ehrenfried/keystrokeqr/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Scan a QR or barcode with your iPhone — the text is typed instantly at the cursor position on your Mac.**

A two-part open-source system that works entirely **on your local Wi-Fi** — no cloud, no accounts, peer-to-peer.

```
┌─────────────┐   Bonjour/mDNS Discovery    ┌──────────────────┐
│   iPhone    │ ──────────────────────────▶ │       Mac        │
│  Scanner    │                             │   Menu bar app   │
│    app      │   WebSocket (local Wi-Fi)   │                  │
│ (SwiftUI +  │ ──────────────────────────▶ │  CGEvent key     │
│AVFoundation)│      {"type":"scan",…}      │  injection ⌨️     │
└─────────────┘                             └──────────────────┘
```

## Components

| Component | Path | Technology |
|---|---|---|
| **macOS host** (menu bar app) | [`macos/`](macos/) | Swift, Network.framework, CGEvent |
| **iOS scanner** (client) | [`ios/`](ios/) | SwiftUI, AVFoundation, Network.framework |
| **Protocol specification** | [`docs/PROTOCOL-v2.md`](docs/PROTOCOL-v2.md) | Bonjour `_keystrokeqr._tcp` + OTP pairing + encrypted session |

📖 **All guides and references: [docs/](docs/README.md)** (installation, setup, protocol, security).

## How it works

1. The **Mac app** starts a local WebSocket server (port 8080, automatic fallback) and advertises it on the Wi-Fi network via **Bonjour** (`_keystrokeqr._tcp`).
2. The **iPhone app** finds the Mac automatically — no IP address needed — and connects.
3. Every detected QR or barcode is sent to the Mac instantly with haptic feedback (1 s scan cooldown to prevent double scans).
4. The Mac types the text as **real keystrokes** (CGEvent, Unicode-safe, layout-independent) into the currently focused window — optionally followed by **Tab** and/or **Enter** (toggleable in the iPhone app).

## Download

The ready-to-use macOS app is available on the **[Releases page](https://github.com/tim-ehrenfried/keystrokeqr/releases/latest)**
(`KeystrokeQR-Host-macOS.dmg`, ad-hoc signed). Installation and
Gatekeeper notes for end users without Xcode: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Quick start

### Mac (first)

```bash
cd macos
make app        # builds "KeystrokeQR Host.app"
open dist/"KeystrokeQR Host.app"
```

⚠️ **Required once:** grant Accessibility permission, otherwise the app can't type:
**System Settings → Privacy & Security → Accessibility → enable "KeystrokeQR Host".**
Details: [macos/README.md](macos/README.md)

### iPhone

```bash
cd ios
open QRKeyboardScanner.xcodeproj
```

In Xcode, select a signing team and install on your iPhone. On first launch, allow camera and local-network access. Details: [ios/README.md](ios/README.md)

## Security & privacy

- **No cloud service**: your data never leaves your Wi-Fi network.
- Connections are local-network only, **end-to-end encrypted**, and only work between devices you explicitly **paired** with a one-time code (since v0.6.0).
- If the connection drops, the iPhone app automatically searches again (Bonjour re-browse with backoff).
- **Threat model, deliberate design decisions, and recommendations: [SECURITY.md](SECURITY.md).** Please report security vulnerabilities by email (responsible disclosure, address listed there).

## Versioning

SemVer, see [CHANGELOG.md](CHANGELOG.md). Current version: **0.14.0**.

## License

MIT — see [LICENSE](LICENSE).
