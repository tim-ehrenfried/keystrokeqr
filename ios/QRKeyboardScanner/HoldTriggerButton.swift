import SwiftUI
import UIKit

/// Auslöser im Stil der Sperrbildschirm-Buttons (Taschenlampe/Kamera):
/// löst NICHT bei Tap oder Touch-Down aus, sondern erst nach bewusstem
/// Gedrückthalten (~0,3 s).
///
/// Verhalten:
/// - Druckbeginn: dezente Haptik, Button wächst leicht an, ein sichtbarer
///   Fortschritt (`progress` 0→1) läuft über die Haltedauer.
/// - Schwelle erreicht: kräftiger haptischer „Pop“ (.rigid), DANN feuert
///   `action` — genau einmal. Weiteres Halten löst NICHT erneut aus.
/// - Loslassen vor der Schwelle: nichts passiert, der Button federt zurück;
///   `onTooShort` erlaubt der UI einen „Zum Senden halten“-Hinweis.
///
/// `label` bekommt Druckzustand + Fortschritt und rendert das eigentliche
/// Erscheinungsbild (Shutter-Kreis, Kapsel, …) selbst.
struct HoldTriggerButton<Label: View>: View {
    var isEnabled = true
    /// Haltedauer bis zur Auslösung — bewusst kurz (0,3 s): schützt weiterhin
    /// vor versehentlichen Taps, fühlt sich aber flotter an als die
    /// Sperrbildschirm-Buttons (~0,45 s). Die Fortschritts-Animation läuft
    /// automatisch über dieselbe Dauer (`withAnimation(.linear(duration:))`).
    var holdDuration: Double = 0.3
    var action: () -> Void
    /// Zu kurz gedrückt (kein Auslösen) — z. B. Hinweistext einblenden.
    var onTooShort: () -> Void = { }
    @ViewBuilder var label: (_ isPressed: Bool, _ progress: Double) -> Label

    @State private var isPressed = false
    @State private var didFire = false
    @State private var progress: Double = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        label(isPressed, progress)
            .scaleEffect(isPressed ? 1.07 : 1.0)
            .animation(.spring(duration: 0.25), value: isPressed)
            .gesture(pressGesture)
            // VoiceOver: direkt aktivierbar (ohne Halten) — die Haltedauer ist
            // ein Schutz gegen versehentliche Berührungen, keine Hürde für
            // Screenreader-Nutzung.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard isEnabled else { return }
                action()
            }
            .onDisappear {
                holdTask?.cancel()
                holdTask = nil
                isPressed = false
                didFire = false
                progress = 0
            }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed, isEnabled else { return }
                beginPress()
            }
            .onEnded { _ in
                endPress()
            }
    }

    private func beginPress() {
        isPressed = true
        didFire = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.linear(duration: holdDuration)) {
            progress = 1
        }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled, isPressed, !didFire else { return }
            didFire = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            action()
        }
    }

    private func endPress() {
        // Nur auswerten, wenn ein Druck tatsächlich begonnen hatte (Taps auf
        // einen deaktivierten Auslöser lösen auch keinen Hinweis aus).
        guard isPressed else { return }
        holdTask?.cancel()
        holdTask = nil
        let fired = didFire
        isPressed = false
        didFire = false
        withAnimation(.spring(duration: 0.3)) {
            progress = 0
        }
        if !fired {
            onTooShort()
        }
    }
}
