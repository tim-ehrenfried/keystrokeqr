import XCTest
import CryptoKit
@testable import QRKeyboardScanner

/// Deckt die Krypto-/Protokoll-Kernlogik ab (docs/PROTOCOL-v2.md). Die exakten
/// Salt-/Info-Strings und das Nonce-Schema MÜSSEN mit dem macOS-Host
/// übereinstimmen — diese Tests pinnen sie fest.
final class CryptoManagerTests: XCTestCase {

    private func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - Nonce-Schema (Richtungspräfix ‖ big-endian seq)

    func testFrameDirectionPrefixes() {
        XCTAssertEqual(FrameDirection.clientToHost, Array("qkc1".utf8))
        XCTAssertEqual(FrameDirection.hostToClient, Array("qkh1".utf8))
    }

    func testNonceIsPrefixPlusBigEndianSeq() throws {
        let nonce = try SecureFrame.nonce(prefix: FrameDirection.clientToHost, seq: 1)
        let bytes = Data(nonce)
        XCTAssertEqual(bytes.count, 12) // 4-Byte-Präfix + 8-Byte-seq
        XCTAssertEqual(Array(bytes.prefix(4)), FrameDirection.clientToHost)
        XCTAssertEqual(Array(bytes.suffix(8)), [0, 0, 0, 0, 0, 0, 0, 1]) // big-endian 1
    }

    // MARK: - ChaChaPoly-Frame (ciphertext‖tag, kein Nonce-Präfix)

    func testSealProducesCiphertextPlusTagWithoutNonce() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 0)
        // ciphertext (== plaintext-Länge bei ChaChaPoly) + 16-Byte-Tag, KEIN 12-Byte-Nonce.
        XCTAssertEqual(ct.count, plaintext.count + 16)
    }

    func testSealOpenRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("Freiburg Wirtschaft Touristik".utf8)
        for seq: UInt64 in [0, 1, 42, .max] {
            let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: seq)
            let opened = try SecureFrame.open(ct, key: key, prefix: FrameDirection.clientToHost, seq: seq)
            XCTAssertEqual(opened, plaintext)
        }
    }

    func testOpenFailsOnSeqMismatch() throws {
        let key = SymmetricKey(size: .bits256)
        let ct = try SecureFrame.seal(Data("x".utf8), key: key, prefix: FrameDirection.clientToHost, seq: 5)
        XCTAssertThrowsError(try SecureFrame.open(ct, key: key, prefix: FrameDirection.clientToHost, seq: 6))
    }

    func testOpenFailsOnDirectionMismatch() throws {
        let key = SymmetricKey(size: .bits256)
        let ct = try SecureFrame.seal(Data("x".utf8), key: key, prefix: FrameDirection.clientToHost, seq: 0)
        // Gegenrichtungs-Präfix ⇒ anderer Nonce ⇒ AEAD-Fehler.
        XCTAssertThrowsError(try SecureFrame.open(ct, key: key, prefix: FrameDirection.hostToClient, seq: 0))
    }

    func testOpenFailsOnTamperedCiphertext() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try SecureFrame.seal(Data("payload".utf8), key: key, prefix: FrameDirection.clientToHost, seq: 0)
        // Über Base64 (wie auf der Leitung) neu materialisieren, damit die Indizes
        // bei 0 beginnen (die rohe seal-Ausgabe ist ein Slice mit versetztem
        // startIndex), dann ein Ciphertext-Byte kippen.
        var ct = Data(base64Encoded: sealed.base64EncodedString())!
        ct[ct.startIndex] ^= 0xFF
        XCTAssertThrowsError(try SecureFrame.open(ct, key: key, prefix: FrameDirection.clientToHost, seq: 0))
    }

    func testOpenFailsOnTooShortInput() {
        let key = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try SecureFrame.open(Data([0, 1, 2]), key: key, prefix: FrameDirection.clientToHost, seq: 0))
    }

    // MARK: - HKDF-Ableitungen (exakte Salt/Info-Strings)

    func testDerivePSKMatchesExplicitHKDF() throws {
        let peer = Curve25519.KeyAgreement.PrivateKey()
        let hostPub = peer.publicKey.rawRepresentation
        let clientPub = CryptoManager.shared.identityPublicKey
        let shared = try CryptoManager.shared.sharedSecret(withPeerPublicKey: hostPub)

        let psk = CryptoManager.shared.derivePSK(shared: shared, clientPub: clientPub, hostPub: hostPub)
        let expected = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-pair-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
        XCTAssertEqual(keyData(psk), keyData(expected))
        XCTAssertEqual(keyData(psk).count, 32)
    }

    func testDeriveConfirmKeyMatchesExplicitHKDF() throws {
        let peer = Curve25519.KeyAgreement.PrivateKey()
        let hostPub = peer.publicKey.rawRepresentation
        let clientPub = CryptoManager.shared.identityPublicKey
        let shared = try CryptoManager.shared.sharedSecret(withPeerPublicKey: hostPub)

        let confirmKey = CryptoManager.shared.deriveConfirmKey(shared: shared, clientPub: clientPub, hostPub: hostPub)
        let expected = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-confirm-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
        XCTAssertEqual(keyData(confirmKey), keyData(expected))
    }

    /// Beide Seiten (Client-Identität + Peer) müssen aus Curve25519 dasselbe PSK
    /// ableiten — echter Pairing-Roundtrip.
    func testPSKAgreesBetweenBothParties() throws {
        let peer = Curve25519.KeyAgreement.PrivateKey()
        let hostPub = peer.publicKey.rawRepresentation
        let clientPub = CryptoManager.shared.identityPublicKey

        let clientShared = try CryptoManager.shared.sharedSecret(withPeerPublicKey: hostPub)
        let clientPSK = CryptoManager.shared.derivePSK(shared: clientShared, clientPub: clientPub, hostPub: hostPub)

        let peerShared = try peer.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPub)
        )
        let peerPSK = peerShared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-pair-v2".utf8),
            sharedInfo: clientPub + hostPub, // Info-Reihenfolge ist clientPub‖hostPub auf beiden Seiten
            outputByteCount: 32
        )
        XCTAssertEqual(keyData(clientPSK), keyData(peerPSK))
    }

    // MARK: - Pairing-HMAC

    func testConfirmationMACMatchesExplicitHMAC() {
        let confirmKey = SymmetricKey(size: .bits256)
        let otp = "123456"
        let mac = CryptoManager.confirmationMAC(otp: otp, confirmKey: confirmKey)
        let expected = Data(HMAC<SHA256>.authenticationCode(for: Data(otp.utf8), using: confirmKey))
        XCTAssertEqual(mac, expected)
        XCTAssertEqual(mac.count, 32)
    }

    func testConfirmationMACDiffersForWrongOTP() {
        let confirmKey = SymmetricKey(size: .bits256)
        let good = CryptoManager.confirmationMAC(otp: "000000", confirmKey: confirmKey)
        let bad = CryptoManager.confirmationMAC(otp: "000001", confirmKey: confirmKey)
        XCTAssertNotEqual(good, bad)
    }

    // MARK: - Sitzungsschlüssel (HKDF über PSK + Nonces)

    func testDeriveSessionKeyMatchesExplicitHKDFAndIsSymmetric() {
        let psk = SymmetricKey(size: .bits256)
        let clientNonce = Data((0..<16).map { UInt8($0) })
        let hostNonce = Data((16..<32).map { UInt8($0) })

        let sessionKey = CryptoManager.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)
        let expected = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: psk,
            salt: clientNonce + hostNonce,
            info: Data("qrkb-session-v2".utf8),
            outputByteCount: 32
        )
        XCTAssertEqual(keyData(sessionKey), keyData(expected))

        // Nonce-Reihenfolge ist signifikant (salt = clientNonce‖hostNonce).
        let swapped = CryptoManager.deriveSessionKey(psk: psk, clientNonce: hostNonce, hostNonce: clientNonce)
        XCTAssertNotEqual(keyData(sessionKey), keyData(swapped))
    }

    /// Ende-zu-Ende: aus PSK Sitzungsschlüssel ableiten, Frame verschlüsseln und
    /// mit demselben Schlüssel/Nonce-Schema wieder entschlüsseln.
    func testSessionKeyFrameRoundtrip() throws {
        let psk = SymmetricKey(size: .bits256)
        let clientNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let hostNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let sessionKey = CryptoManager.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)

        let plaintext = Data("scan payload 42".utf8)
        let ct = try SecureFrame.seal(plaintext, key: sessionKey, prefix: FrameDirection.clientToHost, seq: 7)
        let opened = try SecureFrame.open(ct, key: sessionKey, prefix: FrameDirection.clientToHost, seq: 7)
        XCTAssertEqual(opened, plaintext)
    }

    // MARK: - Keychain-Record-Serialisierung

    func testSymmetricKeyFromRecordRoundtrip() {
        let key = SymmetricKey(size: .bits256)
        let data = keyData(key)
        let restored = CryptoManager.symmetricKey(fromRecord: data)
        XCTAssertEqual(keyData(restored), data)
    }
}
