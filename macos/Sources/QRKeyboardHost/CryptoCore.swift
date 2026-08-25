import Foundation
import CryptoKit

/// Reine, zustandslose Krypto-/Protokoll-Kernfunktionen gemäß
/// docs/PROTOCOL-v2.md. Bewusst frei von Keychain-/UI-/Netzwerk-Abhängigkeiten,
/// damit die sicherheitsrelevante Ableitungs- und Bestätigungslogik isoliert
/// getestet werden kann (`swift test`). `CryptoManager` delegiert an diese
/// Funktionen, ändert also kein Verhalten — es sind exakt dieselben Salt-/Info-
/// Strings und dasselbe HKDF/HMAC-Schema wie zuvor.
enum CryptoCore {

    // MARK: - HKDF-Ableitungen (Salt-/Info-Strings exakt aus PROTOCOL-v2.md)

    /// `PSK = HKDF-SHA256(ikm: shared, salt: "qrkb-pair-v2", info: clientPub‖hostPub, len: 32)`
    static func derivePSK(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-pair-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
    }

    /// `confirmKey = HKDF-SHA256(ikm: shared, salt: "qrkb-confirm-v2", info: clientPub‖hostPub, len: 32)`
    static func deriveConfirmKey(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-confirm-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
    }

    /// `sessionKey = HKDF-SHA256(ikm: PSK, salt: clientNonce‖hostNonce, info: "qrkb-session-v2", len: 32)`
    static func deriveSessionKey(psk: SymmetricKey, clientNonce: Data, hostNonce: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: psk,
            salt: clientNonce + hostNonce,
            info: Data("qrkb-session-v2".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - Pairing-Bestätigung (HMAC über den OTP)

    /// `HMAC-SHA256(key: confirmKey, message: UTF8(OTP))` — der Bestätigungs-MAC,
    /// den der Client sendet (`pair_confirm.mac`).
    static func pairingMAC(otp: String, confirmKey: SymmetricKey) -> Data {
        let code = HMAC<SHA256>.authenticationCode(for: Data(otp.utf8), using: confirmKey)
        return Data(code)
    }

    /// Prüft einen empfangenen Bestätigungs-MAC gegen den erwarteten OTP —
    /// **konstante Zeit** über `HMAC.isValidAuthenticationCode` (docs/PROTOCOL-v2.md,
    /// „Host prüft `mac == expectedMAC` (konstante Zeit)").
    static func isValidPairingMAC(_ mac: Data, otp: String, confirmKey: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(otp.utf8), using: confirmKey)
    }
}
