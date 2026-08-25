import Foundation
import CoreGraphics
import ApplicationServices

/// Tippt empfangenen Text als echte Tastaturanschläge in das aktuell
/// fokussierte Fenster. Unicode-Injection via CGEvent, layout-unabhängig.
/// Alle Scans werden strikt sequenziell auf einer seriellen Queue abgearbeitet.
final class KeyInjector: @unchecked Sendable {

    /// Virtuelle Keycodes (ANSI, layout-unabhängig für Sondertasten).
    private static let keyCodeReturn: CGKeyCode = 36
    private static let keyCodeTab: CGKeyCode = 48

    private let queue = DispatchQueue(label: "de.timehrenfried.keystrokeqr.host.injector")
    private var didPromptForAccessibility = false

    /// Aktueller Accessibility-Status (ohne Prompt).
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Führt einen Scan aus: Text tippen, danach optional Tab und/oder Enter
    /// (Reihenfolge: Text → Tab → Enter). `completion` wird auf der
    /// Injector-Queue aufgerufen; `ok == false` bedeutet fehlende
    /// Accessibility-Berechtigung.
    func perform(text: String, autoTab: Bool, autoEnter: Bool,
                 completion: @escaping @Sendable (_ ok: Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            guard AXIsProcessTrusted() else {
                // Beim ersten Sendeversuch ohne Berechtigung den System-Prompt
                // auslösen (auf dem Main Thread, da UI).
                if !self.didPromptForAccessibility {
                    self.didPromptForAccessibility = true
                    DispatchQueue.main.async {
                        let options = [
                            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                        ] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                }
                completion(false)
                return
            }

            // Geschwindigkeit pro Scan frisch aus den Einstellungen lesen,
            // damit Menü-Änderungen sofort greifen.
            self.typeText(text, speed: TypingSpeed.current)
            if autoTab {
                self.pressKey(Self.keyCodeTab)
            }
            if autoEnter {
                self.pressKey(Self.keyCodeReturn)
            }
            completion(true)
        }
    }

    // MARK: - Private

    /// Tippt beliebigen Unicode-Text in Chunks. Chunk-Größe und Inter-Chunk-
    /// Pause richten sich nach der gewählten `TypingSpeed`. Surrogatpaare
    /// werden nie getrennt.
    private func typeText(_ text: String, speed: TypingSpeed) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        let chunkSize = speed.chunkSize
        let delay = speed.interChunkDelayMicroseconds

        var index = 0
        while index < units.count {
            var end = min(index + chunkSize, units.count)
            // Surrogatpaar nicht trennen: endet der Chunk auf einem
            // High-Surrogate, wandert das Paar in den nächsten Chunk.
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) {
                end -= 1
            }
            var chunk = Array(units[index..<end])

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                up.post(tap: .cghidEventTap)
            }

            // Pause zwischen den Chunks, damit die Zielanwendung die Events in
            // Reihenfolge verarbeitet (größer bei „Langsam“).
            usleep(delay)
            index = end
        }
    }

    /// Sendet eine einzelne Sondertaste (z. B. Tab/Return) als Keycode-Event.
    private func pressKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
        usleep(10_000)
    }
}
