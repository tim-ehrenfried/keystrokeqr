import XCTest
@testable import QRKeyboardScanner

/// Codable-Roundtrips der Protokoll-Nachrichten (docs/PROTOCOL-v2.md). Die
/// JSON-Feldnamen sind Wire-Format und MÜSSEN mit dem macOS-Host übereinstimmen.
final class MessagesCodableTests: XCTestCase {

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testScanMessageEncoding() throws {
        let data = encodeMessage(ScanMessage(text: "ABC-123", autoEnter: true, autoTab: false))
        let obj = try jsonObject(data)
        XCTAssertEqual(obj["type"] as? String, "scan")
        XCTAssertEqual(obj["text"] as? String, "ABC-123")
        XCTAssertEqual(obj["autoEnter"] as? Bool, true)
        XCTAssertEqual(obj["autoTab"] as? Bool, false)
    }

    func testAckMessageDecoding() throws {
        let json = Data(#"{"type":"ack","ok":false,"error":"accessibility_denied"}"#.utf8)
        let ack = try JSONDecoder().decode(AckMessage.self, from: json)
        XCTAssertEqual(ack.type, "ack")
        XCTAssertFalse(ack.ok)
        XCTAssertEqual(ack.error, "accessibility_denied")
    }

    func testAckMessageDecodingWithoutError() throws {
        let json = Data(#"{"type":"ack","ok":true}"#.utf8)
        let ack = try JSONDecoder().decode(AckMessage.self, from: json)
        XCTAssertTrue(ack.ok)
        XCTAssertNil(ack.error)
    }

    func testEncFrameRoundtrip() throws {
        let frame = EncFrameMessage(seq: 9, ct: "YmFzZTY0")
        let data = encodeMessage(frame)
        let obj = try jsonObject(data)
        XCTAssertEqual(obj["type"] as? String, "enc")
        XCTAssertEqual(obj["seq"] as? UInt64, 9)
        XCTAssertEqual(obj["ct"] as? String, "YmFzZTY0")

        let decoded = try JSONDecoder().decode(EncFrameMessage.self, from: data)
        XCTAssertEqual(decoded.type, "enc")
        XCTAssertEqual(decoded.seq, 9)
        XCTAssertEqual(decoded.ct, "YmFzZTY0")
    }

    func testPairHelloEncoding() throws {
        let data = encodeMessage(PairHelloMessage(clientPub: "cHVi", deviceName: "Tims iPhone"))
        let obj = try jsonObject(data)
        XCTAssertEqual(obj["type"] as? String, "pair_hello")
        XCTAssertEqual(obj["clientPub"] as? String, "cHVi")
        XCTAssertEqual(obj["deviceName"] as? String, "Tims iPhone")
    }

    func testPairConfirmEncoding() throws {
        let data = encodeMessage(PairConfirmMessage(mac: "bWFj"))
        let obj = try jsonObject(data)
        XCTAssertEqual(obj["type"] as? String, "pair_confirm")
        XCTAssertEqual(obj["mac"] as? String, "bWFj")
    }

    func testSessionHelloEncoding() throws {
        let data = encodeMessage(SessionHelloMessage(deviceID: "DEV-ID", nonce: "bm9uY2U="))
        let obj = try jsonObject(data)
        XCTAssertEqual(obj["type"] as? String, "session_hello")
        XCTAssertEqual(obj["deviceID"] as? String, "DEV-ID")
        XCTAssertEqual(obj["nonce"] as? String, "bm9uY2U=")
    }

    func testPairOkDecoding() throws {
        let json = Data(#"{"type":"pair_ok","deviceID":"uuid-1","hostName":"Tims MacBook"}"#.utf8)
        let msg = try JSONDecoder().decode(PairOkMessage.self, from: json)
        XCTAssertEqual(msg.deviceID, "uuid-1")
        XCTAssertEqual(msg.hostName, "Tims MacBook")
    }

    func testPairErrorDecoding() throws {
        let json = Data(#"{"type":"pair_error","error":"bad_otp"}"#.utf8)
        let msg = try JSONDecoder().decode(PairErrorMessage.self, from: json)
        XCTAssertEqual(msg.error, "bad_otp")
    }

    func testSessionErrorDecoding() throws {
        let json = Data(#"{"type":"session_error","error":"not_paired"}"#.utf8)
        let msg = try JSONDecoder().decode(SessionErrorMessage.self, from: json)
        XCTAssertEqual(msg.error, "not_paired")
    }

    func testEnvelopeExtractsType() throws {
        let json = Data(#"{"type":"session_ready","nonce":"bm9uY2U="}"#.utf8)
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: json)
        XCTAssertEqual(envelope.type, "session_ready")
    }
}
