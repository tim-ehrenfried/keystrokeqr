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
                    Text("New Mac — pair it once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter the code from the Mac menu “Pair Device…”:")
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
                            Text("Pair")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(otp.count != 6 || isPairing)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Pair Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
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
            return String(localized: "Wrong code. On the Mac, generate a new code via “Pair Device…”.")
        case .expired:
            return String(localized: "The code has expired (90 s). Generate a new code on the Mac.")
        case .closed:
            return String(localized: "The pairing window on the Mac is closed.")
        case .connectionFailed:
            return String(localized: "Connection to the Mac failed. Please try again.")
        case .notFound:
            return String(localized: "Mac not found.")
        case .invalidResponse:
            return String(localized: "Unexpected response from the Mac.")
        }
    }
}
