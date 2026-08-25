import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var connectionManager = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("autoEnter") private var autoEnter = false
    @AppStorage("autoTab") private var autoTab = false

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastScannedText: String?
    @State private var showHelp = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraStatus {
            case .authorized:
                ScannerView(
                    onScan: { text in
                        lastScannedText = text
                        connectionManager.send(text: text, autoEnter: autoEnter, autoTab: autoTab)
                    },
                    isActive: scenePhase == .active
                )
                .ignoresSafeArea()
            case .denied, .restricted:
                CameraDeniedView()
            default:
                ProgressView("Kamera wird vorbereitet …")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                statusCapsule
                if connectionManager.hostAccessibilityDenied {
                    accessibilityWarning
                }
                Spacer()
                controlBar
            }
            .padding()
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
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $connectionManager.showServicePicker) {
            servicePicker
        }
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
