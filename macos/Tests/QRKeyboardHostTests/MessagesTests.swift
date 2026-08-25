import XCTest
@testable import QRKeyboardHost

/// Tests der JSON-Nachrichten (Codable) gemäß docs/PROTOCOL-v2.md — inkl. exakter
/// Feldnamen, damit Host und iOS-Client kompatibel bleiben.
final class MessagesTests: XCTestCase {

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - scan / ack

    func testScanMessageDecodes() throws {
        let json = Data("""
        {"type":"scan","text":"ABC-123","autoEnter":true,"autoTab":false}
        """.utf8)
        let scan = try JSONDecoder().decode(ScanMessage.self, from: json)
        XCTAssertEqual(scan.type, "scan")
        XCTAssertEqual(scan.text, "ABC-123")
        XCTAssertEqual(scan.autoEnter, true)
        XCTAssertEqual(scan.autoTab, false)
    }

    func testScanMessageOptionalFlagsMayBeAbsent() throws {
        let json = Data("{\"type\":\"scan\",\"text\":\"x\"}".utf8)
        let scan = try JSONDecoder().decode(ScanMessage.self, from: json)
        XCTAssertNil(scan.autoEnter)
        XCTAssertNil(scan.autoTab)
    }

    func testAckEncodesFieldsAndType() throws {
        let ok = try jsonObject(AckMessage(ok: true).jsonData())
        XCTAssertEqual(ok["type"] as? String, "ack")
        XCTAssertEqual(ok["ok"] as? Bool, true)

        let fail = try jsonObject(AckMessage(ok: false, error: "accessibility_denied").jsonData())
        XCTAssertEqual(fail["type"] as? String, "ack")
        XCTAssertEqual(fail["ok"] as? Bool, false)
        XCTAssertEqual(fail["error"] as? String, "accessibility_denied")
    }

    // MARK: - Pairing (pair_*)

    func testPairHelloDecodes() throws {
        let json = Data("""
        {"type":"pair_hello","clientPub":"YWJj","deviceName":"Tims iPhone"}
        """.utf8)
        let msg = try JSONDecoder().decode(PairHelloMessage.self, from: json)
        XCTAssertEqual(msg.type, "pair_hello")
        XCTAssertEqual(msg.clientPub, "YWJj")
        XCTAssertEqual(msg.deviceName, "Tims iPhone")
    }

    func testPairChallengeEncodesExactKeys() throws {
        let obj = try jsonObject(encodeMessage(PairChallengeMessage(hostPub: "SG9zdFB1Yg==")))
        XCTAssertEqual(obj["type"] as? String, "pair_challenge")
        XCTAssertEqual(obj["hostPub"] as? String, "SG9zdFB1Yg==")
        XCTAssertEqual(Set(obj.keys), ["type", "hostPub"])
    }

    func testPairConfirmDecodes() throws {
        let json = Data("{\"type\":\"pair_confirm\",\"mac\":\"bWFj\"}".utf8)
        let msg = try JSONDecoder().decode(PairConfirmMessage.self, from: json)
        XCTAssertEqual(msg.type, "pair_confirm")
        XCTAssertEqual(msg.mac, "bWFj")
    }

    func testPairOkEncodesExactKeys() throws {
        let obj = try jsonObject(encodeMessage(
            PairOkMessage(deviceID: "UUID-1", hostName: "Tims MacBook")))
        XCTAssertEqual(obj["type"] as? String, "pair_ok")
        XCTAssertEqual(obj["deviceID"] as? String, "UUID-1")
        XCTAssertEqual(obj["hostName"] as? String, "Tims MacBook")
        XCTAssertEqual(Set(obj.keys), ["type", "deviceID", "hostName"])
    }

    func testPairErrorEncodesExactKeys() throws {
        let obj = try jsonObject(encodeMessage(PairErrorMessage(error: "bad_otp")))
        XCTAssertEqual(obj["type"] as? String, "pair_error")
        XCTAssertEqual(obj["error"] as? String, "bad_otp")
    }

    // MARK: - Sitzung (session_*)

    func testSessionHelloDecodes() throws {
        let json = Data("""
        {"type":"session_hello","deviceID":"DID","nonce":"bm9uY2U="}
        """.utf8)
        let msg = try JSONDecoder().decode(SessionHelloMessage.self, from: json)
        XCTAssertEqual(msg.type, "session_hello")
        XCTAssertEqual(msg.deviceID, "DID")
        XCTAssertEqual(msg.nonce, "bm9uY2U=")
    }

    func testSessionReadyEncodesExactKeys() throws {
        let obj = try jsonObject(encodeMessage(SessionReadyMessage(nonce: "bm9uY2U=")))
        XCTAssertEqual(obj["type"] as? String, "session_ready")
        XCTAssertEqual(obj["nonce"] as? String, "bm9uY2U=")
        XCTAssertEqual(Set(obj.keys), ["type", "nonce"])
    }

    func testSessionErrorEncodesExactKeys() throws {
        let obj = try jsonObject(encodeMessage(SessionErrorMessage(error: "not_paired")))
        XCTAssertEqual(obj["type"] as? String, "session_error")
        XCTAssertEqual(obj["error"] as? String, "not_paired")
    }

    // MARK: - Verschlüsselter Frame (enc)

    func testEncFrameRoundtrip() throws {
        let frame = EncFrameMessage(seq: 42, ct: "Y2lwaGVy")
        let obj = try jsonObject(encodeMessage(frame))
        XCTAssertEqual(obj["type"] as? String, "enc")
        XCTAssertEqual(obj["seq"] as? Int, 42)
        XCTAssertEqual(obj["ct"] as? String, "Y2lwaGVy")

        let decoded = try JSONDecoder().decode(EncFrameMessage.self, from: encodeMessage(frame))
        XCTAssertEqual(decoded.type, "enc")
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.ct, "Y2lwaGVy")
    }

    // MARK: - Envelope + Fehlercodes

    func testEnvelopeReadsType() throws {
        let env = try JSONDecoder().decode(
            MessageEnvelope.self, from: Data("{\"type\":\"enc\",\"seq\":0,\"ct\":\"x\"}".utf8))
        XCTAssertEqual(env.type, "enc")
    }

    func testProtocolErrorRawValues() {
        XCTAssertEqual(ProtocolError.accessibilityDenied.rawValue, "accessibility_denied")
        XCTAssertEqual(ProtocolError.invalidMessage.rawValue, "invalid_message")
        XCTAssertEqual(ProtocolError.payloadTooLarge.rawValue, "payload_too_large")
        XCTAssertEqual(ProtocolErrorV2.badOTP.rawValue, "bad_otp")
        XCTAssertEqual(ProtocolErrorV2.pairingClosed.rawValue, "pairing_closed")
        XCTAssertEqual(ProtocolErrorV2.pairingExpired.rawValue, "pairing_expired")
        XCTAssertEqual(ProtocolErrorV2.notPaired.rawValue, "not_paired")
        XCTAssertEqual(ProtocolErrorV2.badSession.rawValue, "bad_session")
    }
}
