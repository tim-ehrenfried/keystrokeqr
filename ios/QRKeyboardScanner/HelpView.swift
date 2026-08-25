import SwiftUI

/// In-App-Anleitung (Sheet). Basissprache Englisch, Deutsch via String Catalog.
struct HelpView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPairedMacs = false
    @State private var showOnboarding = false

    /// Version + Build dynamisch aus dem Bundle, z. B. „0.7.0 (1)".
    private static var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Introduction") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Show the intro again", systemImage: "sparkles")
                    }
                }

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

                    Button {
                        showPairedMacs = true
                    } label: {
                        Label("Manage paired Macs", systemImage: "lock.desktopcomputer")
                    }
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
                        Text("• Point the camera at a QR or barcode — on recognition the iPhone vibrates briefly, the viewfinder freezes for 1 second and the text is “typed” on the Mac right away.")
                        Text("• **Auto-Enter**: the Return key is sent after the text.")
                        Text("• **Auto-Tab**: the Tab key is sent after the text (with both: Tab first, then Enter).")
                        Text("• The most recently scanned text is shown at the bottom.")
                        Text("• **Tap** the viewfinder to focus on that spot (yellow frame), **pinch** with two fingers to zoom. The camera automatically switches lenses for nearby codes (macro on newer iPhones).")
                        Text("• **Each code is typed automatically only once.** If the same code is scanned again, the app does not send automatically — instead the yellow **“Send again”** button appears at the bottom to transmit the code deliberately once more.")
                        Text("• **Clear history** (⟲ in the control bar) forgets all codes already sent; this also happens automatically on app restart.")
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

                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KeystrokeQR")
                            .font(.headline)
                        Text("Version \(Self.appVersionString)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("© 2026 Tim Ehrenfried")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let mailURL = URL(string: "mailto:mail@tim-ehrenfried.de") {
                        Link(destination: mailURL) {
                            Label("mail@tim-ehrenfried.de", systemImage: "envelope")
                        }
                    }
                    if let repoURL = URL(string: "https://github.com/tim-ehrenfried/keystrokeqr") {
                        Link(destination: repoURL) {
                            Label("Open source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPairedMacs) {
                PairedMacsView(connectionManager: connectionManager)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
            }
        }
    }
}

#Preview {
    HelpView(connectionManager: ConnectionManager())
}
