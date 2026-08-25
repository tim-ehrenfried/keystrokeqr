import SwiftUI
import AVFoundation
import AudioToolbox
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
    /// Sende-Modus: Push-to-Send (Standard) oder Continuous (Auto-Senden).
    @AppStorage("sendMode") private var sendMode: SendMode = .pushToSend
    /// Haptik, wenn tatsächlich gesendet wurde (Default AN).
    @AppStorage("sendHaptics") private var sendHaptics = true
    /// Kurzer System-Ton beim Senden (Default AUS; respektiert Lautlos-Schalter).
    @AppStorage("sendSound") private var sendSound = false
    /// Merkt sich, ob das erste Onboarding einmal durchlaufen wurde.
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showOnboarding = false

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastScannedText: String?
    @State private var showSettings = false
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
    /// Aktuell im Scan-Fenster erkannter Code, der den Auslöser speist:
    /// Push-to-Send → runder Send-Button (jeder erkannte Code);
    /// Continuous → gelber „Erneut senden“-Auslöser (nur bereits gesendete).
    @State private var triggerCandidate: String?
    /// Blendet den Auslöser nach Ablauf ohne erneute Erkennung aus (~2 s Nachlauf).
    @State private var triggerHideTask: Task<Void, Never>?
    /// Kurzes visuelles Feedback + Sperre nach manuellem Senden (~0,9-s-Cooldown
    /// gegen Doppel-Trigger).
    @State private var sendCooldownActive = false
    /// „Zum Senden halten“-Hinweis nach einem zu kurzen Tap auf den Auslöser.
    @State private var showHoldHint = false
    @State private var holdHintTask: Task<Void, Never>?

    /// Markengelb #FFD60A (Auslöser, Scan-Fenster-Klammern).
    private static let accent = ScanWindowOverlay.accent

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
                        handleAutoScan(text)
                    },
                    shouldAutoSend: { [sentRegistry] text in
                        // Push-to-Send sendet NIE automatisch — jede Erkennung
                        // läuft über den (gedrosselten) Detection-Kanal und
                        // speist den Send-Button.
                        sendMode == .continuous && !sentRegistry.contains(text)
                    },
                    onRepeatDetection: { text in
                        handleDetection(text)
                    },
                    isActive: scenePhase == .active,
                    playScanHaptics: sendHaptics,
                    resetToken: scanResetToken,
                    onRunningChanged: { running in
                        isCameraRunning = running
                    }
                )
                .ignoresSafeArea()
                if !isCameraRunning {
                    cameraStartingOverlay
                }
                // Scan-Fenster (1:1, volle Breite, oberhalb der Mitte): außen
                // abgedunkelt, Ausschnitt klar — liegt bewusst ÜBER dem dunklen
                // Kamera-Startzustand, damit das Fenster sofort sichtbar ist.
                ScanWindowOverlay()
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
                if let triggerCandidate {
                    VStack(spacing: 10) {
                        if showHoldHint {
                            holdHintLabel
                        }
                        if sendMode == .pushToSend {
                            sendButton(for: triggerCandidate)
                        } else {
                            resendButton(for: triggerCandidate)
                        }
                    }
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
            .animation(.spring(duration: 0.3), value: triggerCandidate)
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
                triggerCandidate = "Freiburg Wirtschaft Tour…"
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
        .sheet(isPresented: $showSettings) {
            SettingsView(
                connectionManager: connectionManager,
                sentRegistry: sentRegistry,
                onClearHistory: clearHistory
            )
        }
        .onChange(of: sendMode) { _, _ in
            // Moduswechsel: laufenden Auslöser-Zustand verwerfen — der jeweils
            // passende Auslöser baut sich über die nächste Erkennung neu auf.
            triggerHideTask?.cancel()
            triggerCandidate = nil
            showHoldHint = false
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
        .onChange(of: connectionManager.pendingPairingService) { _, service in
            // Nur Simulator-Layout-Preview: Pairing-Angebote automatisch
            // ablehnen, damit die Scanner-UI (Overlay/Auslöser) sichtbar bleibt.
            autoDeclinePairingForLayoutPreview(service)
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

    // MARK: - Bedienleiste unten (schlank: Vorschau, Mac-Wahl, Einstellungen)

    private var controlBar: some View {
        HStack(spacing: 12) {
            if let lastScannedText {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sendMode == .pushToSend ? "Last detected" : "Last scanned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        // Dezente Kennzeichnung im Push-Modus: dieser Code wurde
                        // in dieser Sitzung schon (mindestens einmal) gesendet.
                        if sendMode == .pushToSend, sentRegistry.contains(lastScannedText) {
                            Label("Already sent", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Self.accent.opacity(0.9))
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Text(lastScannedText)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

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
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens settings, help and pairing management.")
        }
        .font(.subheadline)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Erkennungs-/Sende-Logik

    /// Continuous-Modus: neuer Code wurde automatisch erkannt → einmal senden
    /// (Erfolgs-Haptik übernimmt der Scanner, Setting-gesteuert).
    private func handleAutoScan(_ text: String) {
        lastScannedText = text
        sentRegistry.insert(text)
        connectionManager.send(text: text, autoEnter: autoEnter, autoTab: autoTab)
        playSendSoundIfEnabled()
    }

    /// Ein Code ist (weiterhin) im Scan-Fenster — entprellt gemeldet (max. ~4x/s):
    /// Push-to-Send → Send-Button für GENAU diesen Code zeigen/verlängern;
    /// Continuous → „Erneut senden“-Auslöser für bereits gesendete Codes.
    private func handleDetection(_ text: String) {
        if sendMode == .pushToSend {
            lastScannedText = text
        }
        triggerCandidate = text
        triggerHideTask?.cancel()
        triggerHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            triggerCandidate = nil
        }
    }

    /// Push-to-Send: runder Auslöser im Shutter-Stil (Markengelb), unten mittig
    /// über der Bedienleiste. Gedrückt HALTEN (~0,3 s) sendet den aktuell
    /// erkannten Code genau einmal; Halten wiederholt nicht (Cooldown + Einmal-
    /// Auslösung in HoldTriggerButton).
    private func sendButton(for payload: String) -> some View {
        HoldTriggerButton(
            isEnabled: !sendCooldownActive,
            action: { pushSend(payload) },
            onTooShort: { flashHoldHint() }
        ) { isPressed, progress in
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Self.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Self.accent)
                    .padding(7)
                    .brightness(isPressed ? -0.06 : 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 78, height: 78)
        }
        .opacity(sendCooldownActive ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.15), value: sendCooldownActive)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Send: \(payload)"))
        .accessibilityHint("Sends the code currently detected in the scan window to the Mac once.")
    }

    /// Push-to-Send: sendet den aktuell erkannten Code GENAU EINMAL.
    /// Haptik/Ton je nach Setting; Fehler-Haptik, wenn kein Mac verbunden ist.
    private func pushSend(_ payload: String) {
        guard !sendCooldownActive else { return }
        lastScannedText = payload

        var didSend = false
        if case .connected = connectionManager.state {
            sentRegistry.insert(payload)
            connectionManager.send(text: payload, autoEnter: autoEnter, autoTab: autoTab)
            didSend = true
        }
        if sendHaptics {
            UINotificationFeedbackGenerator().notificationOccurred(didSend ? .success : .error)
        }
        if didSend {
            playSendSoundIfEnabled()
        }
        startSendCooldown()
    }

    /// Continuous-Modus: deutlicher Auslöser, der den bereits übertragenen Code
    /// bewusst erneut sendet — ebenfalls per Gedrückthalten.
    private func resendButton(for payload: String) -> some View {
        HoldTriggerButton(
            isEnabled: !sendCooldownActive,
            action: { resend(payload) },
            onTooShort: { flashHoldHint() }
        ) { isPressed, progress in
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
            .background {
                ZStack(alignment: .leading) {
                    Capsule().fill(Self.accent)
                    // Sichtbarer Hold-Fortschritt: die Kapsel „füllt sich".
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.white.opacity(0.45))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .clipShape(Capsule())
            }
            .brightness(isPressed ? -0.04 : 0)
        }
        .opacity(sendCooldownActive ? 0.6 : 1.0)
        .animation(.easeOut(duration: 0.15), value: sendCooldownActive)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Send again: \(payload)"))
        .accessibilityHint("Sends the already-transmitted code to the Mac again.")
    }

    private func resend(_ payload: String) {
        guard !sendCooldownActive else { return }
        lastScannedText = payload
        connectionManager.send(text: payload, autoEnter: autoEnter, autoTab: autoTab)
        if sendHaptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        playSendSoundIfEnabled()
        startSendCooldown()
    }

    /// Cooldown gegen Doppel-Trigger (~0,9 s), gilt für Send- UND Resend-Auslöser.
    private func startSendCooldown() {
        sendCooldownActive = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            sendCooldownActive = false
        }
    }

    /// Kurzer, klar hörbarer Piep beim Senden (Setting `sendSound`, Default AUS).
    /// AudioServices respektiert den Lautlos-Schalter von sich aus.
    ///
    /// Ausprobierte SystemSound-IDs (Auswahl bewusst „Scanner-Piep“-artig):
    /// - 1057 (Tock.caf) — bisheriger Ton: dumpfes Klacken, in lauter Umgebung
    ///   kaum hörbar → verworfen.
    /// - 1103 (Tink.caf) — heller Tastatur-Klick, kurz, aber immer noch eher
    ///   „Klick“ als „Piep“ → verworfen.
    /// - 1052 (SIMToolkitPositiveACK.caf) — kurzer, schriller Bestätigungs-
    ///   Piep (hohe Sinus-Charakteristik), klingt wie ein Handscanner-Beep
    ///   und schneidet auch in lauter Umgebung durch → GEWÄHLT.
    private func playSendSoundIfEnabled() {
        guard sendSound else { return }
        AudioServicesPlaySystemSound(1052) // schriller Scanner-Piep (SIMToolkitPositiveACK)
    }

    /// „Zum Senden halten“-Hinweis: erscheint nach einem zu kurzen Tap auf den
    /// Auslöser und blendet sich nach ~1,8 s wieder aus.
    private var holdHintLabel: some View {
        Text("Hold to send")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func flashHoldHint() {
        withAnimation(.easeOut(duration: 0.2)) {
            showHoldHint = true
        }
        holdHintTask?.cancel()
        holdHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showHoldHint = false
            }
        }
    }

    private func clearHistory() {
        sentRegistry.clear()
        // Im Continuous-Modus ist der „Erneut senden“-Auslöser damit
        // gegenstandslos; im Push-Modus baut sich der Send-Button über die
        // nächste Erkennung (≤ 0,25 s) ohnehin neu auf.
        if sendMode == .continuous {
            triggerHideTask?.cancel()
            triggerCandidate = nil
        }
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

    /// Macht den Scanner sichtbar (Settings-Sheet schließen) und setzt den
    /// Scan-Cooldown zurück, damit sofort gescannt werden kann.
    private func activateScanner() {
        showSettings = false
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        scanResetToken += 1
    }

    /// Nur Simulator + aktivierte Layout-Preview: lehnt Pairing-Angebote
    /// automatisch ab, damit Screenshots die Scanner-UI zeigen statt des
    /// Pairing-Sheets (im Netz gefundene echte Macs würden es sonst öffnen).
    private func autoDeclinePairingForLayoutPreview(_ service: ConnectionManager.DiscoveredService?) {
        #if targetEnvironment(simulator)
        guard Self.simulatorLayoutPreview, let service else { return }
        connectionManager.pendingPairingService = nil
        connectionManager.declinePairing(for: service)
        #endif
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
