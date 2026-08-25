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

/// Fehlercodes laut Protokoll.
enum ProtocolError: String {
    case accessibilityDenied = "accessibility_denied"
    case invalidMessage = "invalid_message"
}
