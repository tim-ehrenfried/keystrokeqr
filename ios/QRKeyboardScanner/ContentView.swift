import SwiftUI
import AVFoundation
import UIKit

/// App-Laufzeit-scoped Registry der bereits gesendeten Payloads.
/// Bewusst nicht persistiert — leert sich bei jedem App-Neustart.
/// Referenztyp, damit die Scanner-Callbacks nie auf veralteten Werten arbeiten.
@MainActor
final class SentRegistry: ObservableObject {
    @Published private(set) var payloads: Set<String> = []

    var isEmpty: Bool { payloads.isEmpty }
    func contains(_ payload: String) -> Bool { payloads.contains(payload) }
    func insert(_ payload: String) { payloads.insert(payload) }
    func clear() { payloads.removeAll() }
}

struct ContentView: View {
    @StateObject private var connectionManager = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("autoEnter") private var autoEnter = false
    @AppStorage("autoTab") private var autoTab = false
    /// Merkt sich, ob das erste Onboarding einmal durchlaufen wurde.
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showOnboarding = false

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastScannedText: String?
    @State private var showHelp = false
    /// Manuell geöffnete „gefundene Macs“-Liste (Wechsel des verbundenen Macs).
    @State private var showMacSwitcher = false
    /// In der Mac-Auswahlliste angetippter Mac, dessen Auswahl (`switchTo`) ERST
    /// nach dem vollständigen Schließen der Liste ausgeführt wird. Verhindert das
    /// Konkurrieren zweier Sheet-Übergänge (Liste ↔ Pairing) im selben Update-
    /// Zyklus — sonst würde der frisch präsentierte Pairing-Screen sofort wieder
    /// abgebaut. Siehe `macListSheet.onDisappear`.
    @State private var pendingMacSelection: ConnectionManager.DiscoveredService?
    /// Wird erhöht, wenn der Scanner (Deep-Link/App Intent) sofort scharf sein
    /// soll — setzt in der ScannerView den Cooldown zurück.
    @State private var scanResetToken = 0
    /// True, sobald die AVCaptureSession tatsächlich Bilder liefert.
    @State private var isCameraRunning = false

    /// Bereits gesendete Codes (nur App-Laufzeit, siehe `SentRegistry`).
    @StateObject private var sentRegistry = SentRegistry()
    /// Bereits gesendeter Code, der gerade im Sucher ist → Auslöser-Button.
    @State private var repeatCandidate: String?
    /// Blendet den Auslöser-Button nach Ablauf ohne erneute Erkennung aus.
    @State private var repeatHideTask: Task<Void, Never>?
    /// Kurzes visuelles Feedback + Sperre nach manuellem Senden (1-s-Cooldown).
    @State private var resendCooldownActive = false
    @State private var showClearConfirmation = false

    #if targetEnvironment(simulator)
    /// Nur Simulator: blendet Auslöser-Kapsel + „Zuletzt gescannt" dauerhaft
    /// mit Dummy-Daten ein, um das Overlay-Layout ohne Kamera zu prüfen.
    /// Zum Verifizieren auf `true` setzen — im Normalzustand deaktiviert.
    private static let simulatorLayoutPreview = false
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraStatus {
            case .authorized:
                ScannerView(
                    onScan: { text in
                        lastScannedText = text
                        sentRegistry.insert(text)
                        connectionManager.send(text: text, autoEnter: autoEnter, autoTab: autoTab)
                    },
                    shouldAutoSend: { [sentRegistry] text in
                        !sentRegistry.contains(text)
                    },
                    onRepeatDetection: { text in
                        handleRepeatDetection(text)
                    },
                    isActive: scenePhase == .active,
                    resetToken: scanResetToken,
                    onRunningChanged: { running in
                        isCameraRunning = running
                    }
                )
                .ignoresSafeArea()
                if !isCameraRunning {
                    cameraStartingOverlay
                }
            case .denied, .restricted:
                CameraDeniedView()
            default:
                cameraStartingOverlay
            }

            VStack(spacing: 12) {
                statusCapsule
                if connectionManager.outdatedHostDetected {
                    outdatedHostWarning
                }
                if connectionManager.hostAccessibilityDenied {
                    accessibilityWarning
                }
                if showPairPrompt {
                    pairMacPrompt
                }
                Spacer(minLength: 0)
                if let repeatCandidate {
                    resendButton(for: repeatCandidate)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controlBar
            }
            // Kamera bleibt Vollbild (ignoresSafeArea), aber alle Overlays
            // respektieren die Safe Area: durchgängig 16 pt Seitenabstand,
            // unten zusätzlich Abstand über dem Home-Indicator.
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .animation(.spring(duration: 0.3), value: repeatCandidate)
        }
        .preferredColorScheme(.dark)
        .task {
            // Beim allerersten Start zuerst das Onboarding zeigen; Kamera-/
            // Netzwerk-Berechtigungen werden erst danach (bzw. kontextuell im
            // Onboarding) angefragt, damit die Prompts nicht ungeklärt auftauchen.
            if didCompleteOnboarding {
                beginRuntime()
            } else {
                showOnboarding = true
            }
            #if targetEnvironment(simulator)
            if Self.simulatorLayoutPreview {
                lastScannedText = "Freiburg Wirtschaft Touristik und Messe GmbH & Co. KG"
                repeatCandidate = "Freiburg Wirtschaft Tour…"
            }
            #endif
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                didCompleteOnboarding = true
                showOnboarding = false
                beginRuntime()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                connectionManager.start()
            } else {
                connectionManager.stop()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .startScanRequested)) { _ in
            activateScanner()
        }
        .sheet(isPresented: $showHelp) {
            HelpView(connectionManager: connectionManager)
        }
        .sheet(isPresented: $connectionManager.showServicePicker) {
            macListSheet
        }
        .sheet(isPresented: $showMacSwitcher) {
            macListSheet
        }
        .sheet(item: $connectionManager.pendingPairingService) { service in
            PairingView(connectionManager: connectionManager, service: service)
        }
        .onChange(of: connectionManager.notPairedServiceName) { _, serviceName in
            guard let serviceName,
                  let service = connectionManager.services.first(where: { $0.name == serviceName }) else { return }
            connectionManager.pendingPairingService = service
            connectionManager.notPairedServiceName = nil
        }
    }

    /// Dunkler Lade-Zustand, bis die Kamera tatsächlich Bilder liefert
    /// (verhindert weißes Aufblitzen nach dem Launch Screen).
    private var cameraStartingOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                Text("Starting camera…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: isCameraRunning)
    }

    // MARK: - Status oben

    private var statusText: String {
        switch connectionManager.state {
        case .idle, .browsing:
            return String(localized: "Searching for Mac…")
        case .connecting:
            return String(localized: "Connecting…")
        case .connected(let name):
            return String(localized: "Connected to \(name)")
        case .disconnected:
            return String(localized: "Disconnected – searching again…")
        }
    }

    private var statusColor: Color {
        switch connectionManager.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .idle, .browsing: return .orange
        }
    }

    private var statusCapsule: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        // Farbiger Punkt ist dekorativ; VoiceOver liest eine sprechende
        // Statuszeile als ein Element (statt Punkt + Text getrennt).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Connection status: \(statusText)"))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibilityWarning: some View {
        Label("Mac: Accessibility permission missing", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.yellow, in: RoundedRectangle(cornerRadius: 12))
            .multilineTextAlignment(.center)
    }

    private var outdatedHostWarning: some View {
        Button {
            connectionManager.outdatedHostDetected = false
        } label: {
            Label("Found Mac is running an outdated app – please update", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.orange, in: RoundedRectangle(cornerRadius: 12))
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    // MARK: - „Mac koppeln“-Hinweis (immer sichtbarer Weg zurück ins Pairing)

    /// True, sobald ein v2-Mac gefunden wurde, der (noch) nicht gekoppelt und
    /// nicht verbunden ist. Dann zeigen wir einen deutlichen „Mac koppeln“-Button
    /// — der Pairing-Screen poppt bewusst NICHT mehr von allein auf (Loop-Fix),
    /// aber der Nutzer kommt hierüber jederzeit ohne App-Neustart zurück zum Koppeln.
    private var showPairPrompt: Bool {
        guard case .connected = connectionManager.state else {
            return connectionManager.hasPairableMac
        }
        return false
    }

    /// Deutlicher, tippbarer Hinweis in der Statuszone: öffnet den Pairing-Screen
    /// (bzw. bei mehreren gefundenen Macs die Mac-Auswahl).
    private var pairMacPrompt: some View {
        Button {
            openPairingEntry()
        } label: {
            Label("Pair Mac", systemImage: "desktopcomputer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.blue, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the pairing screen to connect a found Mac.")
    }

    /// Öffnet den Weg zurück ins Pairing: bei genau einem gefundenen (ungekoppelten)
    /// Mac direkt den Pairing-Screen, sonst die Mac-Auswahlliste, in der man den
    /// gewünschten Mac antippt.
    private func openPairingEntry() {
        let pairable = connectionManager.pairableServices
        if pairable.count == 1 && connectionManager.services.count == 1 {
            connectionManager.beginPairing(for: pairable[0])
        } else {
            showMacSwitcher = true
        }
    }

    // MARK: - Bedienleiste unten

    private var controlBar: some View {
        VStack(spacing: 12) {
            if let lastScannedText {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last scanned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(lastScannedText)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                toggleChip("Auto-Enter", isOn: $autoEnter,
                           hint: "When on, the Return key is sent after each scanned text.")
                toggleChip("Auto-Tab", isOn: $autoTab,
                           hint: "When on, the Tab key is sent after each scanned text.")
                Spacer(minLength: 0)
                if !connectionManager.services.isEmpty {
                    Button {
                        showMacSwitcher = true
                    } label: {
                        Image(systemName: "desktopcomputer")
                            .font(.title2)
                    }
                    .accessibilityLabel("Choose Mac")
                    .accessibilityHint("Shows the list of found Macs to connect or switch.")
                }
                Button {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                }
                .disabled(sentRegistry.isEmpty)
                .accessibilityLabel("Clear history")
                .accessibilityHint("Forgets all codes already sent, so they can be sent automatically again.")
                .confirmationDialog(
                    "Clear scan history?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear history", role: .destructive) {
                        clearHistory()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("After this, all codes will be sent automatically again.")
                }
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help, pairing management and the intro.")
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Kompakte Schalter-Gruppe: Label sitzt direkt am Switch und darf bei
    /// wenig Breite kürzen/schrumpfen. WICHTIG: Kein `.fixedSize()` auf der
    /// Gruppe — eine unschrumpfbare Zeile, die breiter ist als der Platz,
    /// drückt sonst den umgebenden VStack über die Bildschirmränder hinaus
    /// (die Overlays „kleben" dann trotz `.padding(.horizontal)` an den Kanten).
    private func toggleChip(_ title: String, isOn: Binding<Bool>, hint: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityHidden(true)
                .onTapGesture { isOn.wrappedValue.toggle() }
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
                .accessibilityHint(hint)
        }
    }

    // MARK: - Erneut senden (bereits übertragener Code)

    /// Ein bereits gesendeter Code ist (weiterhin) im Sucher: Button anzeigen
    /// bzw. dessen Ausblende-Timer verlängern (kommt entprellt, max. ~4x/s).
    private func handleRepeatDetection(_ text: String) {
        repeatCandidate = text
        repeatHideTask?.cancel()
        repeatHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            repeatCandidate = nil
        }
    }

    /// Deutlicher Auslöser: sendet den bereits übertragenen Code bewusst erneut.
    private func resendButton(for payload: String) -> some View {
        Button {
            resend(payload)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send again")
                        .font(.headline)
                    Text(payload)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.yellow, in: Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(resendCooldownActive ? 0.96 : 1.0)
        .opacity(resendCooldownActive ? 0.6 : 1.0)
        .disabled(resendCooldownActive)
        .animation(.easeOut(duration: 0.15), value: resendCooldownActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Send again: \(payload)"))
        .accessibilityHint("Sends the already-transmitted code to the Mac again.")
        .accessibilityAddTraits(.isButton)
    }

    private func resend(_ payload: String) {
        guard !resendCooldownActive else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        lastScannedText = payload
        connectionManager.send(text: payload, autoEnter: autoEnter, autoTab: autoTab)

        // Cooldown wie beim Scannen: 1 s keine erneute Auslösung.
        resendCooldownActive = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            resendCooldownActive = false
        }
    }

    private func clearHistory() {
        sentRegistry.clear()
        repeatHideTask?.cancel()
        repeatCandidate = nil
    }

    // MARK: - Auswahl / Wechsel bei mehreren Macs

    /// Erreichbare Liste aller gefundenen Macs — dient sowohl der automatischen
    /// Auswahl (mehr als ein Mac gefunden) als auch dem aktiven Wechsel des
    /// verbundenen Macs. Auswahl trennt eine laufende Verbindung sauber und baut
    /// zum gewählten Mac auf (bzw. bietet Pairing, falls dort noch nicht gekoppelt).
    private var macListSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(connectionManager.services) { service in
                        Button {
                            // Auswahl NICHT sofort ausführen: erst die Liste
                            // vollständig schließen, dann in deren `onDisappear`
                            // den Wechsel/das Pairing anstoßen (deterministisch,
                            // sequenziell). Würden wir `switchTo` hier direkt (oder
                            // in einem Task) aufrufen, konkurrierten zwei Sheet-
                            // Übergänge (Liste dismiss ↔ Pairing present) im selben
                            // Zyklus: der Pairing-Screen erschiene kurz und würde
                            // sofort wieder abgebaut („öffnet, schließt sofort").
                            pendingMacSelection = service
                            connectionManager.showServicePicker = false
                            showMacSwitcher = false
                        } label: {
                            HStack {
                                Label(service.name, systemImage: "desktopcomputer")
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 12)
                                macStatusBadge(connectionManager.status(for: service))
                            }
                        }
                    }
                    if connectionManager.services.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Searching for Mac…", systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text("No Mac found yet. Are the iPhone and Mac on the same Wi-Fi, and is the KeystrokeQR Mac app running?")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Tap a Mac to connect. A new Mac is paired once.")
                }
            }
            .navigationTitle("Choose Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        connectionManager.showServicePicker = false
                        showMacSwitcher = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear {
            // Die Liste ist jetzt vollständig geschlossen. Erst JETZT den zuvor
            // angetippten Mac verarbeiten — so ist kein zweites Sheet mehr aktiv,
            // und ein daraufhin präsentierter Pairing-Screen bleibt zuverlässig
            // offen (kein Sheet-Wettlauf). `switchTo` verbindet gekoppelte Macs
            // bzw. öffnet für ungekoppelte den Pairing-Screen und hebt eine
            // frühere Ablehnung dieses Macs auf.
            guard let target = pendingMacSelection else { return }
            pendingMacSelection = nil
            connectionManager.switchTo(target)
        }
    }

    @ViewBuilder
    private func macStatusBadge(_ status: ConnectionManager.MacStatus) -> some View {
        switch status {
        case .connected: macBadge("Connected", .green)
        case .paired:    macBadge("Paired", .blue)
        case .new:       macBadge("New", .orange)
        case .outdated:  macBadge("Update", .red)
        }
    }

    private func macBadge(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.18), in: Capsule())
    }

    // MARK: - Schnellstart (Deep-Link / App Intent)

    /// Behandelt `keystrokeqr://scan` (Widget, Kontrollzentrum, Shortcuts).
    /// Robust: unbekannte Hosts/Pfade werden ignoriert; läuft die App bereits,
    /// wird nur der Scanner sichtbar gemacht und der Cooldown zurückgesetzt.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "keystrokeqr" else { return }
        let target = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        guard target.isEmpty || target == "scan" else { return }
        activateScanner()
    }

    /// Macht den Scanner sichtbar (Hilfe-Sheet schließen) und setzt den
    /// Scan-Cooldown zurück, damit sofort gescannt werden kann.
    private func activateScanner() {
        showHelp = false
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        scanResetToken += 1
    }

    // MARK: - Laufzeitstart (nach Onboarding)

    /// Startet Kamera-Berechtigung + Bonjour-Discovery. Auf dem ersten Start
    /// erst nach Abschluss des Onboardings, sonst direkt beim App-Start.
    private func beginRuntime() {
        requestCameraAccessIfNeeded()
        connectionManager.start()
    }

    // MARK: - Kamera-Berechtigung

    private func requestCameraAccessIfNeeded() {
        guard cameraStatus == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                cameraStatus = granted ? .authorized : .denied
            }
        }
    }
}

#Preview {
    ContentView()
}
