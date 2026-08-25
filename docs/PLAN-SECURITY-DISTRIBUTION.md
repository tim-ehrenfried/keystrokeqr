# Plan: Encryption + Device Pairing (OTP) and Distribution (Store + DMG)

Status: **Planned, not implemented** (as of 2026-08-25, after v0.5.x).
The two efforts close the open items from [SECURITY.md](../SECURITY.md) and make installation Xcode-free, respectively.

---

## Part A — Security: TLS encryption + one-time pairing with OTP

**Goal:** No open security questions left. Only explicitly paired iPhones may send (authenticity), everything is encrypted (confidentiality), host spoofing leads nowhere (the client authenticates the Mac too).

### Concept

1. **Pairing (one-time, OTP from the Mac):**
   - Mac menu: new item **"Pair device…"** → shows a 6-digit one-time code (OTP, valid 60 s) in a popover.
   - iOS: setup screen on first launch (and under "Pair a new device"): pick a Mac from the Bonjour list → type in the OTP.
   - Technically: the OTP authenticates a one-time key exchange (ECDH with Curve25519 via CryptoKit; the OTP enters the confirmation as an HMAC → man-in-the-middle during pairing ruled out). Result: a long-lived, device-specific **32-byte PSK (pre-shared key)**.
   - Storage: Mac keychain (list of paired devices: name, public key hash, PSK), iOS keychain (one PSK per Mac).
2. **Ongoing connections: TLS-PSK**
   - `Network.framework` on both sides with `NWProtocolTLS` + `sec_protocol_options_add_pre_shared_key` (TLS 1.2 PSK ciphers; no certificate theater needed, the PSK authenticates both sides at once).
   - Unpaired clients: the TLS handshake fails → they can neither send nor eavesdrop. That closes findings 1 (LAN injection), 3 (sniffing), and 4 (host spoofing) from SECURITY.md.
3. **Device management (Mac menu):** list of paired iPhones with "Remove" (revokes the PSK immediately). Admin ground rule: pairing UI only on the Mac, never triggerable remotely.
4. **Protocol v2:** TXT record `v=2`; pairing messages (`pair_request`/`pair_confirm`) run over a separate, unencrypted, strictly limited endpoint ONLY while the pairing popover is open. Hard cut instead of backwards compatibility (both apps come from one repo; old clients show "Please update the app and pair").

### Work packages & effort

| # | Package | Effort |
|---|---|---|
| A1 | PROTOCOL.md v2 (pairing flow, TLS-PSK, error codes `not_paired`, `pairing_expired`) | small |
| A2 | Mac: pairing UI (popover + OTP generator), keychain store, device list in the menu | medium |
| A3 | Mac: switch the listener to TLS-PSK (PSK lookup via client hint) | medium |
| A4 | iOS: setup/pairing screen, keychain, connection on TLS-PSK | medium |
| A5 | Update SECURITY.md (findings 1/3/4 → closed), docs/help | small |

Risk: the TLS-PSK API of Network.framework is poorly documented (DispatchData handling) — plan for possibly 1 extra iteration. Total: ~1 focused development day with agents, easily splittable into 2 releases (pairing+PSK first, then polish).

---

## Part B — Distribution & CI/CD: App Store + notarized DMG

**Target user experience:** get the iOS app from the **App Store** → get the Mac server as a **DMG** from GitHub (notarized, no Gatekeeper fiddling) → pair → done. No Xcode for end users.

### B1 — macOS: signed + notarized DMG (independent of the Store, do this first)

1. **Prerequisites (one-time, manual):** create a **Developer ID Application** certificate in the dev account; create an App Store Connect **API key** (.p8, key ID, issuer ID) for notarization.
2. **GitHub secrets:** certificate as base64 .p12 + password, ASC API key (3 secrets).
3. **Extend the release workflow:** `make app SIGN_IDENTITY="Developer ID Application: …"` → build the DMG (`create-dmg` or `hdiutil`, with an /Applications symlink and background image) → `xcrun notarytool submit --wait` → `xcrun stapler staple` → DMG as a release asset (replaces the zip).
4. **Effect:** the download opens without a warning; the Accessibility permission sticks thanks to a stable signature. INSTALL.md shrinks to "download, drag, grant permission".
5. Optional later: **Sparkle** for auto-updates from the GitHub releases.

### B2 — iOS: TestFlight → App Store

1. **One-time in App Store Connect:** register the bundle IDs (app + widget extension), create the app record, privacy declarations ("Privacy Nutrition Label": no data collection), screenshots (iPhone 6.7"/6.1"), description; review note that the app needs a local Mac counterpart (include a link + test video — important, otherwise there's a rejection risk of "app appears non-functional").
2. **CI:** GitHub Actions with **Fastlane** (`build_app` + `upload_to_testflight` / `deliver`), signing via the ASC API key (cloud-managed certificates, no match repo needed). Trigger: tag `v*` → TestFlight build; manual workflow dispatch → "Submit for review".
3. **Versioning:** derive MARKETING_VERSION from the git tag, build number = GitHub run number.
4. **Phases:** (1) TestFlight internal (usable immediately, also for colleagues), (2) App Store review. Realistically 1–3 review rounds; the pairing from part A should be in BEFORE that (a reviewer on a foreign network + an unauthenticated keystroke server would be substantively problematic too).

### Recommended order

1. **A (security/pairing)** — closes the security gaps and is a prerequisite for a clean Store presence.
2. **B1 (notarized DMG)** — a small, immediate win for distributing the server.
3. **B2 (TestFlight → App Store)** — the longest part due to review/metadata.
