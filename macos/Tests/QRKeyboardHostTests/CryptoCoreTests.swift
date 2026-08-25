import XCTest
import CryptoKit
@testable import QRKeyboardHost

/// Tests der reinen Krypto-Kernlogik (HKDF-Ableitungen + Pairing-HMAC) gemäß
/// docs/PROTOCOL-v2.md. Prüft insbesondere die exakten Salt-/Info-Strings über
/// das beobachtbare Verhalten (Determinismus, beidseitige Übereinstimmung,
/// Trennung der abgeleiteten Schlüssel).
final class CryptoCoreTests: XCTestCase {

    // MARK: - PSK / confirmKey

    func testPSKMatchesOnBothSidesAndIs32Bytes() throws {
        let hs = try TestKeys.handshake()
        let pskClient = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let pskHost = CryptoCore.derivePSK(shared: hs.sharedHost, clientPub: hs.clientPub, hostPub: hs.hostPub)
        XCTAssertEqual(pskClient.rawData, pskHost.rawData, "PSK muss auf Client- und Host-Seite identisch sein")
        XCTAssertEqual(pskClient.rawData.count, 32)
    }

    func testConfirmKeyDiffersFromPSK() throws {
        let hs = try TestKeys.handshake()
        let psk = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let confirm = CryptoCore.deriveConfirmKey(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        // Unterschiedliche Salt-Strings ("qrkb-pair-v2" vs "qrkb-confirm-v2") ⇒
        // klar verschiedene Schlüssel.
        XCTAssertNotEqual(psk.rawData, confirm.rawData)
        XCTAssertEqual(confirm.rawData.count, 32)
    }

    func testPSKIsDeterministic() throws {
        let hs = try TestKeys.handshake()
        let a = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let b = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        XCTAssertEqual(a.rawData, b.rawData)
    }

    func testPSKDependsOnPublicKeyOrder() throws {
        let hs = try TestKeys.handshake()
        // Das `info` ist clientPub‖hostPub — vertauschte Reihenfolge ⇒ anderer Key.
        let normal = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let swapped = CryptoCore.derivePSK(shared: hs.sharedClient, clientPub: hs.hostPub, hostPub: hs.clientPub)
        XCTAssertNotEqual(normal.rawData, swapped.rawData)
    }

    func testDifferentHandshakesYieldDifferentPSKs() throws {
        let a = try TestKeys.handshake()
        let b = try TestKeys.handshake()
        let pskA = CryptoCore.derivePSK(shared: a.sharedClient, clientPub: a.clientPub, hostPub: a.hostPub)
        let pskB = CryptoCore.derivePSK(shared: b.sharedClient, clientPub: b.clientPub, hostPub: b.hostPub)
        XCTAssertNotEqual(pskA.rawData, pskB.rawData)
    }

    // MARK: - sessionKey

    func testSessionKeyDeterministicAndMatchesBothSides() {
        let psk = SymmetricKey(size: .bits256)
        let clientNonce = Data((0..<16).map { UInt8($0) })
        let hostNonce = Data((0..<16).map { UInt8(255 - $0) })

        let k1 = CryptoCore.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)
        let k2 = CryptoCore.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)
        XCTAssertEqual(k1.rawData, k2.rawData)
        XCTAssertEqual(k1.rawData.count, 32)
    }

    func testSessionKeyChangesWithNonces() {
        let psk = SymmetricKey(size: .bits256)
        let clientNonce = Data(repeating: 1, count: 16)
        let hostNonceA = Data(repeating: 2, count: 16)
        let hostNonceB = Data(repeating: 3, count: 16)
        let a = CryptoCore.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonceA)
        let b = CryptoCore.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonceB)
        XCTAssertNotEqual(a.rawData, b.rawData)
    }

    func testSessionKeyNonceOrderMatters() {
        let psk = SymmetricKey(size: .bits256)
        let n1 = Data(repeating: 0xAA, count: 16)
        let n2 = Data(repeating: 0xBB, count: 16)
        // salt = clientNonce‖hostNonce — Vertauschen ⇒ anderer Key.
        let a = CryptoCore.deriveSessionKey(psk: psk, clientNonce: n1, hostNonce: n2)
        let b = CryptoCore.deriveSessionKey(psk: psk, clientNonce: n2, hostNonce: n1)
        XCTAssertNotEqual(a.rawData, b.rawData)
    }

    // MARK: - Pairing-HMAC (Bestätigung)

    func testCorrectOTPVerifies() throws {
        let hs = try TestKeys.handshake()
        let confirmKey = CryptoCore.deriveConfirmKey(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let otp = "429073"
        let mac = CryptoCore.pairingMAC(otp: otp, confirmKey: confirmKey)
        XCTAssertTrue(CryptoCore.isValidPairingMAC(mac, otp: otp, confirmKey: confirmKey))
    }

    func testWrongOTPFails() throws {
        let hs = try TestKeys.handshake()
        let confirmKey = CryptoCore.deriveConfirmKey(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let mac = CryptoCore.pairingMAC(otp: "429073", confirmKey: confirmKey)
        XCTAssertFalse(CryptoCore.isValidPairingMAC(mac, otp: "000000", confirmKey: confirmKey))
    }

    func testConfirmKeyMismatchFails() throws {
        let a = try TestKeys.handshake()
        let b = try TestKeys.handshake()
        let keyA = CryptoCore.deriveConfirmKey(shared: a.sharedClient, clientPub: a.clientPub, hostPub: a.hostPub)
        let keyB = CryptoCore.deriveConfirmKey(shared: b.sharedClient, clientPub: b.clientPub, hostPub: b.hostPub)
        let otp = "123456"
        let mac = CryptoCore.pairingMAC(otp: otp, confirmKey: keyA)
        // Ein MITM ohne den echten confirmKey kann den MAC nicht reproduzieren.
        XCTAssertFalse(CryptoCore.isValidPairingMAC(mac, otp: otp, confirmKey: keyB))
    }

    func testMalformedMACFails() throws {
        let hs = try TestKeys.handshake()
        let confirmKey = CryptoCore.deriveConfirmKey(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let otp = "246810"
        XCTAssertFalse(CryptoCore.isValidPairingMAC(Data([0x00, 0x01, 0x02]), otp: otp, confirmKey: confirmKey))
        XCTAssertFalse(CryptoCore.isValidPairingMAC(Data(), otp: otp, confirmKey: confirmKey))
    }

    /// Verifiziert über CryptoKit direkt, dass `pairingMAC` genau
    /// HMAC-SHA256(confirmKey, UTF8(OTP)) ist (Feld-/Schema-Treue zur Spec).
    func testPairingMACEqualsHMACSHA256() throws {
        let hs = try TestKeys.handshake()
        let confirmKey = CryptoCore.deriveConfirmKey(shared: hs.sharedClient, clientPub: hs.clientPub, hostPub: hs.hostPub)
        let otp = "555444"
        let mac = CryptoCore.pairingMAC(otp: otp, confirmKey: confirmKey)
        let expected = Data(HMAC<SHA256>.authenticationCode(for: Data(otp.utf8), using: confirmKey))
        XCTAssertEqual(mac, expected)
        XCTAssertEqual(mac.count, 32)
    }
}
