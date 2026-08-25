import SwiftUI
import AVFoundation

/// Mehrstufiges First-Run-Onboarding im dunklen App-Design.
///
/// Erscheint beim allerersten Start genau einmal (Persistenz über
/// `@AppStorage("didCompleteOnboarding")` in `ContentView`) und ist später
/// jederzeit erneut über die Hilfe aufrufbar. Vier Seiten mit Paging-Indikator,
/// „Weiter“/„Überspringen“ und einer Berechtigungs-Seite, die den Kamera-Prompt
/// kontextuell auslöst und den Prompt fürs lokale Netzwerk ankündigt.
struct OnboardingView: View {
    /// Wird aufgerufen, wenn das Onboarding beendet wird (fertig oder
    /// übersprungen).
    var onFinish: () -> Void

    @State private var page = 0
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    /// Akzentgelb der Marke (#FFD60A), passend zur Scan-Linie.
    private static let accent = Color(red: 1.0, green: 0.839, blue: 0.039)
    private static let pageCount = 4

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.02, blue: 0.04),
                         Color(red: 0.10, green: 0.11, blue: 0.13)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < Self.pageCount - 1 {
                        Button("Skip") { finish() }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(height: 44)

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    howItWorksPage.tag(1)
                    permissionsPage.tag(2)
                    pairingPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                pageIndicator
                    .padding(.bottom, 8)

                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
    }

    // MARK: - Seiten

    private var welcomePage: some View {
        OnboardingPage(
            icon: "qrcode.viewfinder",
            accent: Self.accent,
            title: "Welcome to KeystrokeQR",
            message: "Scan a QR or barcode with your iPhone and hold the send button — your Mac types it instantly, as if you had entered it on the keyboard."
        )
    }

    private var howItWorksPage: some View {
        OnboardingPage(
            icon: "wifi",
            accent: Self.accent,
            title: "How it works",
            message: "iPhone and Mac talk directly over your local Wi-Fi. Nothing goes through the cloud, and every connection is paired and end-to-end encrypted."
        )
    }

    private var permissionsPage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: "lock.shield")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(Self.accent)
                .accessibilityHidden(true)

            Text("Permissions")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("KeystrokeQR needs two permissions to do its job:")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            VStack(spacing: 14) {
                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    detail: "To read QR and barcodes."
                ) {
                    cameraStatusBadge
                }
                permissionRow(
                    icon: "network",
                    title: "Local network",
                    detail: "To find your Mac and send scans to it. iOS asks for this the first time scanning starts."
                ) {
                    EmptyView()
                }
            }

            if cameraStatus == .notDetermined {
                Button {
                    requestCamera()
                } label: {
                    Text("Allow camera access")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Self.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }

    private var pairingPage: some View {
        OnboardingPage(
            icon: "desktopcomputer.and.arrow.down",
            accent: Self.accent,
            title: "Pair with your Mac",
            message: "On your Mac, open the KeystrokeQR menu and choose “Pair Device…”. It shows a 6-digit code — type it here once when your iPhone finds the Mac. That’s it."
        )
    }

    // MARK: - Bausteine

    private func permissionRow<Trailing: View>(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Self.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var cameraStatusBadge: some View {
        switch cameraStatus {
        case .authorized:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .accessibilityLabel("Camera access granted")
        case .denied, .restricted:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
                .accessibilityLabel("Camera access denied")
        default:
            EmptyView()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Self.accent : Color.white.opacity(0.25))
                    .frame(width: index == page ? 22 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
        .accessibilityHidden(true)
    }

    private var bottomButton: some View {
        Button {
            if page < Self.pageCount - 1 {
                withAnimation { page += 1 }
            } else {
                finish()
            }
        } label: {
            Text(page < Self.pageCount - 1 ? "Continue" : "Let’s go")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Self.accent, in: Capsule())
                .foregroundStyle(.black)
        }
    }

    // MARK: - Aktionen

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                cameraStatus = granted ? .authorized : .denied
            }
        }
    }

    private func finish() {
        onFinish()
    }
}

/// Einheitliche Standard-Seite (Icon, Titel, Fließtext), zentriert.
private struct OnboardingPage: View {
    let icon: String
    let accent: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 84, weight: .light))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.35), radius: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
