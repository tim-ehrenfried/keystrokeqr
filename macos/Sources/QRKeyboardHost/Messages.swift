import Foundation

/// Client → Host: Scan-Nachricht gemäß docs/PROTOCOL.md (v1).
struct ScanMessage: Decodable {
    let type: String
    let text: String
    let autoEnter: Bool?
    let autoTab: Bool?
}

/// Host → Client: Acknowledgement gemäß docs/PROTOCOL.md (v1).
struct AckMessage: Encodable {
    let type = "ack"
    let ok: Bool
    let error: String?

    init(ok: Bool, error: String? = nil) {
        self.ok = ok
        self.error = error
    }

    func jsonData() -> Data {
        let encoder = JSONEncoder()
        // Kompakte, stabile Ausgabe.
        return (try? encoder.encode(self)) ?? Data("{\"type\":\"ack\",\"ok\":false}".utf8)
    }
}

/// Fehlercodes laut Protokoll (v1).
enum ProtocolError: String {
    case accessibilityDenied = "accessibility_denied"
    case invalidMessage = "invalid_message"
    case payloadTooLarge = "payload_too_large"
}

// MARK: - v2 (Pairing + verschlüsselte Sitzung) — siehe docs/PROTOCOL-v2.md

/// Zusätzliche Fehlercodes v2.
enum ProtocolErrorV2: String {
    case badOTP = "bad_otp"
    case pairingClosed = "pairing_closed"
    case pairingExpired = "pairing_expired"
    case notPaired = "not_paired"
    case badSession = "bad_session"
}

func encodeMessage<T: Encodable>(_ value: T) -> Data {
    (try? JSONEncoder().encode(value)) ?? Data()
}

/// Generische Hülle, nur um vor dem eigentlichen Decode das `type`-Feld zu lesen.
struct MessageEnvelope: Decodable {
    let type: String
}

// Phase 1 – Pairing (nur im Pairing-Fenster gültig, Klartext)

struct PairHelloMessage: Decodable {
    let type: String
    let clientPub: String
    let deviceName: String
}

struct PairChallengeMessage: Encodable {
    let type = "pair_challenge"
    let hostPub: String
}

struct PairConfirmMessage: Decodable {
    let type: String
    let mac: String
}

struct PairOkMessage: Encodable {
    let type = "pair_ok"
    let deviceID: String
    let hostName: String
}

struct PairErrorMessage: Encodable {
    let type = "pair_error"
    let error: String
}

// Phase 2 – Gesicherte Sitzung (jede normale Verbindung)

struct SessionHelloMessage: Decodable {
    let type: String
    let deviceID: String
    let nonce: String
}

struct SessionReadyMessage: Encodable {
    let type = "session_ready"
    let nonce: String
}

struct SessionErrorMessage: Encodable {
    let type = "session_error"
    let error: String
}

/// Verschlüsselter Frame (beide Richtungen). `ct` = Base64(ChaChaPoly
/// ciphertext‖tag) — siehe `SecureFrame` für die Nonce-Rekonstruktion.
struct EncFrameMessage: Codable {
    let type: String
    let seq: UInt64
    let ct: String

    init(seq: UInt64, ct: String) {
        self.type = "enc"
        self.seq = seq
        self.ct = ct
    }
}
