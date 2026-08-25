import Foundation
import CryptoKit

/// Steuert das Pairing-Fenster gemäß docs/PROTOCOL-v2.md „Phase 1 – Pairing“
/// inkl. „Fehlerbehandlung & Wiederholung (verbindlich, ab v0.8.0)“:
/// Erzeugt einen 6-stelligen OTP (90 s gültig, `SystemRandomNumberGenerator`).
/// Pro OTP-Wert wird genau EIN `pair_confirm`-Versuch zugelassen (kein
/// Brute-Force). Ist der Versuch falsch, wird der alte OTP verworfen und
/// **sofort ein neuer** OTP mit frischem 90-s-Fenster erzeugt — jeder Rateversuch
/// zielt so gegen einen anderen Zufallscode.
final class PairingCoordinator: @unchecked Sendable {

    /// Ereignisse, die das Pairing-Fenster (Main Thread) verarbeitet.
    enum PairingEvent {
        case paired(name: String)
        /// Falscher Code — ein neuer OTP wurde erzeugt (mitgeliefert), Fenster
        /// bleibt offen, Countdown zurückgesetzt.
        case wrongCodeNewIssued(newOTP: String)
        /// Ein Versuch traf ein abgelaufenes/geschlossenes Fenster.
        case expiredOrClosed
    }

    /// Ergebnis eines `pair_confirm`-Versuchs — steuert die Host-Antwort.
    enum ConfirmOutcome {
        case success
        /// Falscher Code; ein frischer OTP wurde erzeugt.
        case wrongCode(newOTP: String)
        case pairingClosed
        case pairingExpired
    }

    private struct Session {
        let otp: String
        let deadline: Date
        var attemptUsed = false
    }

    private let lock = NSLock()
    private var session: Session?

    /// Wird auf dem Main Thread aufgerufen (Pairing-Fenster hört zu).
    var onEvent: (@Sendable (PairingEvent) -> Void)?

    // MARK: - Session-Lebenszyklus

    private static func randomOTP() -> String {
        var generator = SystemRandomNumberGenerator()
        let value = Int.random(in: 0...999_999, using: &generator)
        return String(format: "%06d", value)
    }

    /// Startet ein neues 90-Sekunden-Fenster mit frischem OTP.
    @discardableResult
    func startSession() -> String {
        let otp = Self.randomOTP()
        lock.lock()
        session = Session(otp: otp, deadline: Date().addingTimeInterval(90))
        lock.unlock()
        return otp
    }

    /// Erzeugt sofort einen neuen OTP und setzt den 90-s-Timer zurück
    /// (nach falschem Code oder auf Nutzerwunsch „Neuen Code erzeugen“).
    @discardableResult
    func regenerate() -> String {
        let otp = Self.randomOTP()
        lock.lock()
        session = Session(otp: otp, deadline: Date().addingTimeInterval(90))
        lock.unlock()
        return otp
    }

    /// Schließt das Fenster; laufende Pairing-Versuche schlagen danach mit
    /// `pairing_closed` fehl.
    func endSession() {
        lock.lock()
        session = nil
        lock.unlock()
    }

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let session else { return false }
        return Date() < session.deadline
    }

    var remainingSeconds: Int {
        lock.lock(); defer { lock.unlock() }
        guard let session else { return 0 }
        return max(0, Int(session.deadline.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: - Bestätigung

    /// Prüft `pair_confirm`. Bei falschem Code wird der OTP verworfen und
    /// **sofort ein neuer** erzeugt (frisches 90-s-Fenster), zurückgegeben als
    /// `.wrongCode(newOTP:)`. Erfolg konsumiert den OTP (kein zweiter Versuch
    /// gegen denselben Code).
    func attemptConfirm(mac: Data, confirmKey: SymmetricKey) -> ConfirmOutcome {
        lock.lock()
        guard var current = session else {
            lock.unlock()
            return .pairingClosed
        }
        guard Date() < current.deadline else {
            session = nil
            lock.unlock()
            return .pairingExpired
        }
        guard !current.attemptUsed else {
            // Defensiv: sollte nicht auftreten, da wir nach jedem Versuch neu
            // erzeugen. Trotzdem sauber einen neuen Code ausgeben.
            lock.unlock()
            return .wrongCode(newOTP: regenerate())
        }
        current.attemptUsed = true
        session = current
        let otp = current.otp
        lock.unlock()

        let isValid = HMAC<SHA256>.isValidAuthenticationCode(
            mac, authenticating: Data(otp.utf8), using: confirmKey
        )
        if isValid {
            return .success
        }
        // Falscher Code: alten OTP verwerfen, sofort neuen erzeugen.
        return .wrongCode(newOTP: regenerate())
    }
}
