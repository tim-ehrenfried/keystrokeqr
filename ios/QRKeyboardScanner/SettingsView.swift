import SwiftUI

/// Sende-Modus des Scanners (persistiert via @AppStorage("sendMode")).
enum SendMode: String, CaseIterable, Identifiable {
    /// Standard: live erkennen, aber erst der gehaltene Send-Button überträgt.
    case pushToSend
    /// Bisheriges Verhalten: jeder neue Code wird automatisch einmal gesendet.
    case continuous

    var id: String { rawValue }
}

/// Zentrale Einstellungen (Sheet, dunkles App-Design): bündelt Sende-Optionen,
/// Verlauf, Mac-Verwaltung sowie Hilfe/Über/Einführung. Ersetzt seit v0.15.0
/// den früheren Hilfe-Button in der Bedienleiste.
struct SettingsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @ObservedObject var sentRegistry: SentRegistry
    /// Leert den Scan-Verlauf (inkl. UI-Zustand in ContentView).
    var onClearHistory: () -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage("sendMode") private var sendMode: SendMode = .pushToSend
    @AppStorage("autoEnter") private var autoEnter = false
    @AppStorage("autoTab") private var autoTab = false
    @AppStorage("sendHaptics") private var sendHaptics = true
    @AppStorage("sendSound") private var sendSound = false

    @State private var showPairedMacs = false
    @State private var showOnboarding = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Send mode", selection: $sendMode) {
                        Text("Push to send").tag(SendMode.pushToSend)
                        Text("Continuous").tag(SendMode.continuous)
                    }
                    Toggle("Auto-Enter", isOn: $autoEnter)
                        .accessibilityHint("When on, the Return key is sent after each scanned text.")
                    Toggle("Auto-Tab", isOn: $autoTab)
                        .accessibilityHint("When on, the Tab key is sent after each scanned text.")
                    Toggle("Haptics on send", isOn: $sendHaptics)
                    Toggle("Sound on send", isOn: $sendSound)
                } header: {
                    Text("Sending")
                } footer: {
                    Text(sendModeFootnote)
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear history", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(sentRegistry.isEmpty)
                    .accessibilityHint("Forgets all codes already sent, so they can be sent automatically again.")
                    .confirmationDialog(
                        "Clear scan history?",
                        isPresented: $showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear history", role: .destructive) {
                            onClearHistory()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("After this, all codes will be sent automatically again.")
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Codes already sent are forgotten automatically on every app restart.")
                }

                Section("Macs") {
                    Button {
                        showPairedMacs = true
                    } label: {
                        Label("Manage paired Macs", systemImage: "lock.desktopcomputer")
                    }
                }

                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Show the intro again", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Settings")
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

    private var sendModeFootnote: LocalizedStringKey {
        switch sendMode {
        case .pushToSend:
            return "The scanner detects codes live, but nothing is sent automatically: hold down the round send button briefly to transmit the detected code — exactly once per hold."
        case .continuous:
            return "Every newly detected code is sent automatically once. If the same code is scanned again, the yellow “Send again” trigger appears."
        }
    }
}

/// „Über“-Seite (früher Abschnitt in der Hilfe): Version, Copyright, Kontakt.
/// Kontakt-/Infrastruktur-Einträge (E-Mail, Landing-Page, Mac-Host-Download)
/// kommen aus `BrandingConfig` und erscheinen nur in offiziellen Builds
/// (`OFFICIAL_BUILD`); Community-Builds zeigen stattdessen einen neutralen
/// Hinweis. Der GitHub-Link (Quellcode, MIT) ist bewusst immer sichtbar.
struct AboutView: View {
    /// Version + Build dynamisch aus dem Bundle, z. B. „0.16.0 (1)“.
    private static var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
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
                if let email = BrandingConfig.contactEmail,
                   let mailURL = URL(string: "mailto:\(email)") {
                    Link(destination: mailURL) {
                        Label {
                            Text(verbatim: email)
                        } icon: {
                            Image(systemName: "envelope")
                        }
                    }
                }
                if let landingURL = BrandingConfig.landingPageURL,
                   let host = landingURL.host {
                    Link(destination: landingURL) {
                        Label {
                            Text(verbatim: host)
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                }
                if let macURL = BrandingConfig.macDownloadURL {
                    Link(destination: macURL) {
                        Label("Download the latest Mac host", systemImage: "arrow.down.circle")
                    }
                    .accessibilityHint("Opens the download page for the KeystrokeQR Mac app in the browser.")
                }
                Link(destination: BrandingConfig.repositoryURL) {
                    Label("Open source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } footer: {
                if !BrandingConfig.isOfficialBuild {
                    Text("Community build — source & issues on GitHub")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView(
        connectionManager: ConnectionManager(),
        sentRegistry: SentRegistry(),
        onClearHistory: { }
    )
}
