# Final Release Phase — Signing, Store, Going Public

The step-by-step playbook for taking KeystrokeQR from "feature-complete"
(v0.16.x) to a public release: App Store + TestFlight for iOS, a notarized
DMG for macOS, and the public landing page. Steps are ordered; each block
says **who** does it — `[Tim]` = needs your Apple ID/password/portal access,
`[Claude]` = I do it on request, `[Tim+Claude]` = we do it together.

**Current status (already done):** features final, E2E encryption + pairing,
tests in CI, English docs, brand icon set, landing page built (private
`gh-pages` branch, `/ios` + `/mac` redirect stubs), `OFFICIAL_BUILD` branding
gating (release pipeline builds official, community builds stay neutral).

---

## Phase 0 — Pre-flight (≈ 30 min) `[Tim+Claude]`

1. **Full E2E regression on real hardware** `[Tim]`: pair fresh, scan (push
   mode + continuous), typing speed, confirm-before-typing, remove device →
   re-pair, Mac onboarding QR scans correctly with the iPhone camera, sound
   check (beep 1052), landing links open.
2. **Secrets audit** `[Claude]`: re-run the repo/history scan for keys,
   tokens, personal data before the repo goes public (was clean at last
   check; re-verify right before flipping).
3. **Version**: decide the public launch version (suggestion: bump to
   **v1.0.0** when everything below is done — SemVer signal "first stable").

---

## Phase 1 — Apple Developer portal: identifiers & keys (≈ 20 min) `[Tim]`

> This unblocks the original Xcode Cloud export failure
> ("Automatic signing cannot register bundle identifier …widgets").

1. [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list)
   → **+** → App IDs → App. Register **explicit** IDs (no capabilities needed
   beyond defaults):
   - `de.timehrenfried.keystrokeqr` (iOS app)
   - `de.timehrenfried.keystrokeqr.widgets` (widget extension)
   - `de.timehrenfried.keystrokeqr.host` (macOS app — for notarization/Developer ID later)
2. **Certificates** (same portal, Certificates):
   - **Developer ID Application** — for the notarized DMG (create via Xcode:
     Settings → Accounts → Manage Certificates → **+** → Developer ID
     Application; needs the paid account).
3. **App Store Connect API key** (for notarization + CI):
   [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)
   → **+** → role **Developer** (App Manager if it should also upload builds)
   → download the `.p8` **once** and note **Key ID** + **Issuer ID**.
   Store the `.p8` in `~/.secrets/` — never in the repo.

---

## Phase 2 — App Store Connect record (≈ 45 min) `[Tim+Claude]`

1. `[Tim]` [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   My Apps → **+** → New App: platform iOS, name **KeystrokeQR** (fallbacks
   if taken: "KeystrokeQR — Scan to Type"), primary language **English**,
   bundle ID `de.timehrenfried.keystrokeqr`, SKU `keystrokeqr-ios`.
2. `[Claude]` I prepare all metadata texts for you to paste (or via API once
   the key exists): description (en + de), keywords, promotional text,
   support URL `https://keystrokeqr.tim-ehrenfried.de/support.html`,
   privacy policy URL `https://keystrokeqr.tim-ehrenfried.de/privacy.html`
   *(these URLs must be live → do Phase 5 DNS/Pages **before** submitting
   for review, or temporarily use the GitHub Pages default URL)*.
3. **App privacy** `[Tim]` (5 clicks): "Data not collected" — the app
   collects nothing (matches privacy.html).
4. **Screenshots** `[Tim+Claude]`: required 6.7" (and 6.1") — take on the
   iPhone (scanner with scan window + shutter, settings, pairing); I crop
   and frame them.
5. **Review notes** (critical — the app "does nothing" without the Mac):
   attach a short demo **video** (iPhone scanning → Mac typing) + text
   explaining the Mac companion (link to the landing page + GitHub) and that
   pairing needs a local Mac. This prevents the classic "app appears
   non-functional" rejection.

---

## Phase 3 — iOS: TestFlight → App Store (days–weeks, review-bound)

**Path A (recommended — Xcode Cloud, already half set up):** `[Tim+Claude]`
1. `[Claude]` Wire the `OFFICIAL_BUILD` flag for Xcode Cloud builds: commit
   a small xcconfig with an **optional include**
   (`#include? "Official.xcconfig"`) attached to the app/widget configs, plus
   a `ci_scripts/ci_post_clone.sh` that writes
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) OFFICIAL_BUILD` into
   `Official.xcconfig` (gitignored). Community builds stay neutral; Xcode
   Cloud/official builds get the branding.
2. `[Tim]` In Xcode → Report navigator → Cloud: re-run the archive workflow
   (the Phase-1 identifiers fix the export). Keep only the **App Store**
   export; drop ad-hoc/development exports from the workflow.
3. Build lands in **TestFlight** automatically → add yourself (internal
   testing starts instantly, no review) → real-device install via TestFlight.
4. When happy: App Store Connect → select the build → **Submit for review**.
   Expect 1–3 review rounds; typical first response within 24–48 h.
5. **After approval**: note the App Store URL
   (`https://apps.apple.com/app/idXXXXXXXXX`) → `[Claude]` I swap the
   redirect in `gh-pages:ios.html` to it (the Mac onboarding QR then leads
   straight to the store) and set the App Store badge link on the landing
   page.

**Path B (fallback — local upload, no Xcode Cloud):** archive in Xcode
(`Product → Archive`, official flag set) → Distribute → App Store Connect.
Same store steps afterwards.

---

## Phase 4 — macOS: signed + notarized DMG (≈ 1 h) `[Tim+Claude]`

**Status:** `release.yml` already has the conditional signing/notarization
block (`.github/workflows/release.yml`, step *"Developer-ID: signieren +
notarisieren"*) and `macos/Makefile` has the `notarize` target — both wired
up and tested locally (ad-hoc path unchanged). All that's missing are the
five GitHub secrets below; once they exist, the **next tag** produces a
notarized DMG automatically. Nothing else to build.

### 1. `[Tim]` Export the Developer ID certificate as `.p12`

In **Keychain Access** (`Keychain Access.app`) → login keychain → *My
Certificates*: find **"Developer ID Application: Tim Ehrenfried (TEAMID)"**,
expand it to see the private key underneath, select **both** the
certificate *and* the private key (⌘-click), right-click → **Export 2
items…** → format **Personal Information Exchange (.p12)** → save as
e.g. `~/Desktop/developer-id.p12` → set a strong export password when
prompted (this becomes `MACOS_CERT_PASSWORD` below).

### 2. `[Tim]` Base64-encode it and set the GitHub secrets

Run from a terminal (repo checked out, `gh` CLI authenticated,
`cd` into the repo first so `gh secret set` targets the right repo):

```sh
# 1) Certificate, base64 → clipboard, paste as the secret value
base64 -i ~/Desktop/developer-id.p12 | pbcopy
gh secret set MACOS_CERT_P12
# → paste (⌘V), confirm with Ctrl-D

# 2) Certificate export password (the one you set in step 1)
gh secret set MACOS_CERT_PASSWORD
# → type/paste the password, confirm with Ctrl-D

# 3) App Store Connect API key trio (from Phase 1 — Key ID, Issuer ID, and
#    the .p8 file stored in ~/.secrets/)
gh secret set ASC_KEY_ID
# → paste the Key ID, confirm with Ctrl-D

gh secret set ASC_ISSUER_ID
# → paste the Issuer ID (UUID), confirm with Ctrl-D

base64 -i ~/.secrets/AuthKey_XXXXXXXXXX.p8 | gh secret set ASC_KEY_P8
```

(Replace `AuthKey_XXXXXXXXXX.p8` with the actual filename from Phase 1.)
Verify all five landed: `gh secret list` should show `MACOS_CERT_P12`,
`MACOS_CERT_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.

Afterwards, securely delete the local `.p12` export
(`rm ~/Desktop/developer-id.p12`) — the secret is now in GitHub, no need to
keep a plaintext copy lying around.

### 3. `[Tim]` Cut a release tag — that's it

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

`release.yml` detects the secrets, re-signs the app + DMG with the
Developer ID identity (hardened runtime + secure timestamp), submits to
`notarytool`, staples the ticket, verifies with `spctl`/`stapler validate`,
and uploads the notarized DMG as the release asset. Watch the run under
**Actions** — the signing step logs the identity it picked and the
`notarytool submit --wait` output (accepted/rejected + any issues).
Cleanup of the temporary keychain and key files happens automatically,
even if a step fails.

If any of the five secrets is missing or empty, the pipeline silently
falls back to the previous ad-hoc-only behavior and logs a
`::warning::` in the Actions run explaining why — so a partially-configured
secret set never blocks a release, it just ships unsigned like before.

### 4. Result

**No Gatekeeper friction** for end users — download, open, drag, done.
`docs/INSTALL.md`'s Gatekeeper section already has the "as of vX, this no
longer applies" paragraph prepared as an **HTML comment** right above the
ad-hoc instructions — after the first notarized release lands, uncomment
it, replace `vX` with the actual version tag, and remove the `TODO(Tim)`
note above it.

### 5. Optional (post-launch)

**Sparkle** auto-updates fed from GitHub releases, so DMG users get updates
in-app.

---

## Phase 5 — Going public (≈ 30 min, the "flip") `[Tim+Claude]`

Order matters — do this only when Phases 1–4 are green:

1. `[Claude]` Final secrets re-scan + docs once-over (versions, links).
2. `[Tim says go, Claude executes]` **Repo → public**
   (`gh repo edit --visibility public`). MIT + English docs are ready.
3. `[Claude]` **Enable GitHub Pages** from `gh-pages`, custom domain
   `keystrokeqr.tim-ehrenfried.de`, enforce HTTPS.
4. `[Tim or Claude via Cloudflare]` **DNS**: 
   `CNAME  keystrokeqr  →  tim-ehrenfried.github.io` (DNS-only/grey cloud
   until the GitHub certificate is issued, then optionally proxied).
5. `[Claude]` Verify: landing page live over HTTPS, `/ios` + `/mac`
   redirects work, download button serves the notarized DMG, README badges
   render, QR from the Mac onboarding resolves on a phone **not** on your
   Wi-Fi (mobile data).
6. Announce wherever you like. 🎉

---

## Rollback / safety nets

- **Repo back to private** is possible at any time (`gh repo edit
  --visibility private`) — Pages goes dark automatically; already-cloned
  copies stay out there (that's why the secrets audit gates the flip).
- **Store**: an approved app can be removed from sale in App Store Connect
  ("Remove from sale") without deleting the record.
- **DMG**: releases can be deleted/replaced; `/mac` always points at
  `releases/latest`.

## Quick reference — what only Tim can do

| Step | Why |
|---|---|
| Portal identifiers, certificates, ASC API key | Apple ID + password |
| App Store Connect record, privacy answers, submit for review | account owner |
| GitHub secrets | repo admin secrets UI |
| Screenshots/demo video on the real iPhone | physical device |
| The go for "repo public" | irreversible-ish decision |

Everything else in this document is scripted or executed by Claude on request.
