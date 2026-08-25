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

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastScannedText: String?
    @State private var showHelp = false
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
                if connectionManager.hostAccessibilityDenied {
                    accessibilityWarning
                }
                Spacer()
                if let repeatCandidate {
                    resendButton(for: repeatCandidate)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controlBar
            }
            .padding()
            .animation(.spring(duration: 0.3), value: repeatCandidate)
        }
        .preferredColorScheme(.dark)
        .task {
            requestCameraAccessIfNeeded()
            connectionManager.start()
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
            HelpView()
        }
        .sheet(isPresented: $connectionManager.showServicePicker) {
            servicePicker
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
                Text("Kamera wird gestartet …")
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
            return "Suche Mac …"
        case .connecting:
            return "Verbinde …"
        case .connected(let name):
            return "Verbunden mit \(name)"
        case .disconnected:
            return "Getrennt – suche erneut …"
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
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var accessibilityWarning: some View {
        Label("Mac: Bedienungshilfen-Berechtigung fehlt", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.yellow, in: RoundedRectangle(cornerRadius: 12))
            .multilineTextAlignment(.center)
    }

    // MARK: - Bedienleiste unten

    private var controlBar: some View {
        VStack(spacing: 12) {
            if let lastScannedText {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuletzt gescannt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(lastScannedText)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 16) {
                Toggle("Auto-Enter", isOn: $autoEnter)
                    .fixedSize()
                Toggle("Auto-Tab", isOn: $autoTab)
                    .fixedSize()
                Spacer()
                Button {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                }
                .disabled(sentRegistry.isEmpty)
                .accessibilityLabel("Verlauf leeren")
                .confirmationDialog(
                    "Scan-Verlauf leeren?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Verlauf leeren", role: .destructive) {
                        clearHistory()
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Danach werden alle Codes wieder automatisch gesendet.")
                }
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
                .accessibilityLabel("Hilfe")
            }
            .toggleStyle(.switch)
            .font(.subheadline)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                    Text("Erneut senden")
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
        .accessibilityHint("Sendet den bereits übertragenen Code noch einmal an den Mac.")
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

    // MARK: - Auswahl bei mehreren Macs

    private var servicePicker: some View {
        NavigationStack {
            List(connectionManager.services) { service in
                Button {
                    connectionManager.connect(to: service)
                } label: {
                    Label(service.name, systemImage: "desktopcomputer")
                }
            }
            .navigationTitle("Mac auswählen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Schnellstart (Deep-Link / App Intent)

    /// Behandelt `qrkeyboard://scan` (Widget, Kontrollzentrum, Shortcuts).
    /// Robust: unbekannte Hosts/Pfade werden ignoriert; läuft die App bereits,
    /// wird nur der Scanner sichtbar gemacht und der Cooldown zurückgesetzt.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "qrkeyboard" else { return }
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
