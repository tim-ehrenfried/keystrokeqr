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
    @State private var didPair = false
    @State private var errorMessage: String?
    @FocusState private var otpFieldFocused: Bool

    private var deviceName: String {
        UIDevice.current.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: didPair ? "checkmark.circle.fill" : "desktopcomputer")
                        .font(.system(size: 44))
                        .foregroundStyle(didPair ? .green : .yellow)
                        .contentTransition(.symbolEffect(.replace))
                    Text(service.name)
                        .font(.headline)
                    Text(didPair ? "Paired ✓" : "New Mac — pair it once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                if !didPair {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter the code from the Mac menu “Pair Device…”:")
                            .font(.subheadline)
                        TextField("000000", text: $otp)
                            .keyboardType(.numberPad)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .focused($otpFieldFocused)
                            .disabled(isPairing)
                            .onChange(of: otp) { _, newValue in
                                let filtered = String(newValue.filter(\.isNumber).prefix(6))
                                if filtered != newValue { otp = filtered }
                                // Tippt der Nutzer nach einem Fehler neu, den
                                // Hinweis ausblenden — der Screen bleibt ruhig.
                                if errorMessage != nil { errorMessage = nil }
                            }
                            .onSubmit { pair() }
                    }

                    // Statuszeile: klar sichtbarer Fehler ODER laufender Versuch.
                    Group {
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else if isPairing {
                            Label {
                                Text("Pairing…")
                            } icon: {
                                ProgressView().controlSize(.small)
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 20)

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
                }

                Spacer()
            }
            .padding(24)
            .animation(.easeInOut(duration: 0.2), value: didPair)
            .navigationTitle("Pair Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !didPair {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancel() }
                    }
                }
            }
            .onAppear { otpFieldFocused = true }
        }
        .presentationDetents([.medium])
        // Während eines laufenden Versuchs und nach Erfolg (Auto-Close) kein
        // versehentliches Wegwischen.
        .interactiveDismissDisabled(isPairing || didPair)
        .onDisappear {
            // Auffangnetz für ALLE Schließ-Wege (Cancel-Button, Wegwischen): war
            // es kein Erfolg, gilt der Mac als abgelehnt, damit die automatische
            // Discovery ihn nicht sofort wieder aufpoppt. Idempotent zu cancel().
            if !didPair {
                connectionManager.declinePairing(for: service)
            }
        }
    }

    private func cancel() {
        // Bewusster Abbruch: Screen schließen UND den Mac als „abgelehnt" merken,
        // damit die automatische Discovery ihn nicht sofort wieder aufpoppt
        // (sonst käme man nur per App-Neustart aus dem Pairing heraus). Der Mac
        // bleibt über den Mac-Auswahl-Button manuell koppelbar.
        connectionManager.declinePairing(for: service)
        dismiss()
    }

    private func pair() {
        guard otp.count == 6, !isPairing else { return }
        isPairing = true
        errorMessage = nil
        otpFieldFocused = false
        Task {
            // Jeder Aufruf baut eine frische Pairing-Verbindung auf (neuer
            // `pair_hello`) — nach einem falschen Code also gegen den neuen
            // OTP des Macs (siehe ConnectionManager.pair(with:otp:deviceName:)).
            let result = await connectionManager.pair(with: service, otp: otp, deviceName: deviceName)
            isPairing = false
            switch result {
            case .success:
                // Erfolg: kurzes „Paired ✓"-Feedback, dann Screen automatisch
                // schließen; ContentView verbindet danach zur Sitzung.
                didPair = true
                try? await Task.sleep(for: .milliseconds(900))
                connectionManager.pendingPairingService = nil
                dismiss()
            case .failure(let error):
                // Sofortige, klare Rückmeldung statt Timeout: Feld leeren,
                // Fokus zurück, auf dem Pairing-Screen bleiben.
                errorMessage = Self.message(for: error)
                otp = ""
                otpFieldFocused = true
            }
        }
    }

    private static func message(for error: ConnectionManager.PairingError) -> String {
        switch error {
        case .badOTP:
            return String(localized: "Wrong code – please try again. A new code is on the Mac.")
        case .expired:
            return String(localized: "The code has expired (90 s). Generate a new code on the Mac.")
        case .closed:
            return String(localized: "The pairing window on the Mac is closed. Reopen it and try again.")
        case .connectionFailed:
            return String(localized: "Connection to the Mac failed. Please try again.")
        case .timedOut:
            return String(localized: "No response from the Mac. Please try again.")
        case .notFound:
            return String(localized: "Mac not found.")
        case .invalidResponse:
            return String(localized: "Unexpected response from the Mac.")
        }
    }
}
