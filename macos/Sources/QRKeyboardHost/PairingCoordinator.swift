import Foundation
import CryptoKit

/// Steuert das Pairing-Fenster gemäß docs/PROTOCOL-v2.md „Phase 1 – Pairing“:
/// Erzeugt einen 6-stelligen OTP (90 s gültig, `SystemRandomNumberGenerator`),
/// akzeptiert genau EINEN `pair_confirm`-Versuch pro OTP (kein Brute-Force
/// über mehrere Versuche — das OTP wird beim ersten Versuch verbraucht,
/// unabhängig vom Ergebnis).
final class PairingCoordinator: @unchecked Sendable {

    enum PairingEvent {
        case paired(name: String)
        case failed(reason: String)
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

    /// Startet ein neues 90-Sekunden-Fenster mit frischem OTP.
    @discardableResult
    func startSession() -> String {
        var generator = SystemRandomNumberGenerator()
        let value = Int.random(in: 0...999_999, using: &generator)
        let otp = String(format: "%06d", value)
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

    /// Prüft `pair_confirm`. Konsumiert das OTP beim ersten Versuch IMMER
    /// (unabhängig vom Ergebnis). Rückgabe: `nil` bei Erfolg, sonst Fehlercode
    /// (`bad_otp` | `pairing_closed` | `pairing_expired`).
    func attemptConfirm(mac: Data, confirmKey: SymmetricKey) -> String? {
        lock.lock()
        guard var current = session else {
            lock.unlock()
            return "pairing_closed"
        }
        guard Date() < current.deadline else {
            session = nil
            lock.unlock()
            return "pairing_expired"
        }
        guard !current.attemptUsed else {
            lock.unlock()
            return "bad_otp"
        }
        current.attemptUsed = true
        session = current
        let otp = current.otp
        lock.unlock()

        let isValid = HMAC<SHA256>.isValidAuthenticationCode(
            mac, authenticating: Data(otp.utf8), using: confirmKey
        )
        return isValid ? nil : "bad_otp"
    }
}
