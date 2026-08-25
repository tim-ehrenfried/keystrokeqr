import SwiftUI

/// In-App-Anleitung. Seit v0.15.0 keine eigene Sheet-Wurzel mehr, sondern eine
/// Unterseite der Einstellungen (SettingsView) — dort liegen auch „Über“,
/// „Gekoppelte Macs verwalten“ und „Einführung erneut anzeigen“.
/// Basissprache Englisch, Deutsch via String Catalog.
struct HelpView: View {
    var body: some View {
        List {
            Section("Requirements") {
                Label {
                    Text("iPhone and Mac are on the **same Wi-Fi** (or the same local network).")
                } icon: {
                    Image(systemName: "wifi")
                }
                Label {
                    Text("The **KeystrokeQR Mac app is running** on the Mac (menu bar icon visible).")
                } icon: {
                    Image(systemName: "desktopcomputer")
                }
                Label {
                    Text("The Mac has granted **Accessibility permission** — only then can it simulate keystrokes.")
                } icon: {
                    Image(systemName: "accessibility")
                }
                // Nur in offiziellen Builds (OFFICIAL_BUILD): direkter Weg zum
                // aktuellen Mac-Host — Community-Builds bleiben neutral.
                if let macURL = BrandingConfig.macDownloadURL {
                    Link(destination: macURL) {
                        Label("Download the latest Mac host", systemImage: "arrow.down.circle")
                    }
                    .accessibilityHint("Opens the download page for the KeystrokeQR Mac app in the browser.")
                }
            }

            Section("One-time pairing") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The connection is **encrypted and paired** — only explicitly paired iPhones can trigger keystrokes on the Mac.")
                    Text("1. On the Mac, open the KeystrokeQR menu → **“Pair Device…”**.")
                    Text("2. The Mac shows a **6-digit code** (valid for 90 seconds).")
                    Text("3. When your iPhone finds a new Mac, the pairing screen appears automatically — enter the code and tap **Pair**.")
                    Text("4. Pairing is **one-time**: the shared key is stored securely in the keychain and used automatically for every future connection.")
                }
                .font(.callout)
            }

            Section("Allow Accessibility on the Mac") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. On the Mac, open **System Settings**.")
                    Text("2. Choose **Privacy & Security → Accessibility**.")
                    Text("3. Enable **KeystrokeQR Host** in the list (add it with “+” if needed).")
                    Text("4. If the app was already running: quit it once and relaunch.")
                }
                .font(.callout)
            }

            Section("Usage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• The app automatically looks for Macs and connects to the first one found. If several are found, a picker appears.")
                    Text("• Only codes inside the square **scan window** are detected — the area around it is dimmed. The most recently detected text is shown at the bottom.")
                    Text("• **Push to send** (default): the scanner detects continuously but sends nothing on its own. As soon as a code is in the scan window, the round yellow send button appears — **hold it briefly** (like the Lock Screen flashlight button) to transmit the code exactly once.")
                    Text("• **Continuous**: each code is typed automatically once. If the same code is scanned again, the yellow **“Send again”** trigger appears — hold it briefly to transmit the code deliberately once more.")
                    Text("• **Auto-Enter**: the Return key is sent after the text.")
                    Text("• **Auto-Tab**: the Tab key is sent after the text (with both: Tab first, then Enter).")
                    Text("• **Tap** the viewfinder to focus on that spot (yellow frame), **pinch** with two fingers to zoom. The camera automatically switches lenses for nearby codes (macro on newer iPhones).")
                    Text("• **Clear history** (Settings → History) forgets all codes already sent; this also happens automatically on app restart.")
                }
                .font(.callout)
            }

            Section("Quick start from the Lock Screen") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Lock Screen widget:** press and hold the Lock Screen → **Customize** → pick the Lock Screen → tap the widget area → add **KeystrokeQR**. Tapping it opens the scanner directly.")
                    Text("**iOS 18 – Controls:** while customizing the Lock Screen, replace one of the two bottom controls (flashlight/camera) with **“Scan QR Code”**. The same control can also be added to **Control Center**.")
                    Text("**Action Button (iPhone 15 Pro and newer):** Settings → **Action Button** → **Shortcut** → choose the **“Scan QR Code”** action.")
                    Text("**Siri/Spotlight:** say “Scan QR Code with KeystrokeQR” or search Spotlight for “scan”.")
                }
                .font(.callout)
            }

            Section("Troubleshooting") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**No Mac found?**")
                    Text("• Check that the iPhone allows the app to access the **local network**: Settings → Apps → KeystrokeQR → Local Network.")
                    Text("• Check that the iPhone and Mac are really on the same network (no guest Wi-Fi, no VPN blocking local traffic).")
                    Text("• The **macOS firewall** must not block incoming connections for KeystrokeQR: System Settings → Network → Firewall → Options.")
                    Divider()
                    Text("**Connected, but nothing is typed?**")
                    Text("• Usually the Accessibility permission is missing on the Mac (see above) — the app shows a warning in that case.")
                    Text("• Make sure the desired input field is focused on the Mac.")
                    Divider()
                    Text("**“Please update the Mac app”?**")
                    Text("• The Mac found is still running the old, unencrypted version. Install the new version on the Mac.")
                    Divider()
                    Text("**Pairing fails / wrong code?**")
                    Text("• Codes are valid for only 90 seconds and are **one-time** — on the Mac, generate a new code via “Pair Device…” and enter it promptly.")
                }
                .font(.callout)
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
