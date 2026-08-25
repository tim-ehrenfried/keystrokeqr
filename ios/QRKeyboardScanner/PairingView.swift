import SwiftUI

/// Pairing-Screen: OTP vom Mac eintippen (docs/PROTOCOL-v2.md, Phase 1).
/// Erscheint, sobald ein v2-Host gefunden wurde, für den noch kein PSK
/// vorliegt (`ConnectionManager.pendingPairingService`).
struct PairingView: View {
    @ObservedObject var connectionManager: ConnectionManager
    let service: ConnectionManager.DiscoveredService
    @Environment(\.dismiss) private var dismiss

    @State private var otp = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @FocusState private var otpFieldFocused: Bool

    private var deviceName: String {
        UIDevice.current.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow)
                    Text(service.name)
                        .font(.headline)
                    Text("Neuer Mac — bitte einmalig koppeln.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Code aus dem Mac-Menü „Gerät koppeln…“ eingeben:")
                        .font(.subheadline)
                    TextField("000000", text: $otp)
                        .keyboardType(.numberPad)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .focused($otpFieldFocused)
                        .onChange(of: otp) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(6))
                            if filtered != newValue { otp = filtered }
                        }
                        .onSubmit { pair() }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    pair()
                } label: {
                    Group {
                        if isPairing {
                            ProgressView()
                        } else {
                            Text("Koppeln")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(otp.count != 6 || isPairing)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Mac koppeln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { cancel() }
                }
            }
            .onAppear { otpFieldFocused = true }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isPairing)
    }

    private func cancel() {
        connectionManager.pendingPairingService = nil
        dismiss()
    }

    private func pair() {
        guard otp.count == 6, !isPairing else { return }
        isPairing = true
        errorMessage = nil
        Task {
            let result = await connectionManager.pair(with: service, otp: otp, deviceName: deviceName)
            isPairing = false
            switch result {
            case .success:
                connectionManager.pendingPairingService = nil
                dismiss()
            case .failure(let error):
                errorMessage = Self.message(for: error)
                otp = ""
            }
        }
    }

    private static func message(for error: ConnectionManager.PairingError) -> String {
        switch error {
        case .badOTP:
            return "Falscher Code. Am Mac im Menü „Gerät koppeln…“ einen neuen Code erzeugen."
        case .expired:
            return "Der Code ist abgelaufen (90 s). Am Mac einen neuen Code erzeugen."
        case .closed:
            return "Das Pairing-Fenster am Mac ist geschlossen."
        case .connectionFailed:
            return "Verbindung zum Mac fehlgeschlagen. Bitte erneut versuchen."
        case .notFound:
            return "Mac nicht gefunden."
        case .invalidResponse:
            return "Unerwartete Antwort vom Mac."
        }
    }
}
