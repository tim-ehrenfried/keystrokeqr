import XCTest
import CryptoKit
@testable import QRKeyboardHost

/// Tests des verschlüsselten Frame-Formats (ChaChaPoly, `ciphertext‖tag`, Nonce
/// aus Richtungspräfix + big-endian seq) gemäß docs/PROTOCOL-v2.md.
final class SecureFrameTests: XCTestCase {

    private let key = SymmetricKey(size: .bits256)

    // MARK: - Nonce-Konstruktion

    func testNonceIsPrefixPlusBigEndianSeq() throws {
        let seq: UInt64 = 0x0102030405060708
        let nonce = try SecureFrame.nonce(prefix: FrameDirection.hostToClient, seq: seq)
        let bytes = Data(nonce)
        XCTAssertEqual(bytes.count, 12)
        XCTAssertEqual(Array(bytes.prefix(4)), FrameDirection.hostToClient)
        XCTAssertEqual(Array(bytes.suffix(8)), [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    }

    func testDirectionPrefixesDiffer() {
        XCTAssertNotEqual(FrameDirection.clientToHost, FrameDirection.hostToClient)
        XCTAssertEqual(FrameDirection.clientToHost.count, 4)
        XCTAssertEqual(FrameDirection.hostToClient.count, 4)
    }

    // MARK: - Roundtrip

    func testSealOpenRoundtrip() throws {
        let plaintext = Data("{\"type\":\"scan\",\"text\":\"hällo 👍\"}".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 7)
        // Kein Nonce-Präfix vorangestellt (nur ciphertext‖tag).
        XCTAssertEqual(ct.count, plaintext.count + 16)
        let opened = try SecureFrame.open(ct, key: key, prefix: FrameDirection.clientToHost, seq: 7)
        XCTAssertEqual(opened, plaintext)
    }

    func testOpenWithWrongSeqFails() throws {
        let plaintext = Data("hello".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 3)
        XCTAssertThrowsError(
            try SecureFrame.open(ct, key: key, prefix: FrameDirection.clientToHost, seq: 4),
            "Falsche seq ⇒ falscher Nonce ⇒ AEAD schlägt fehl")
    }

    func testOpenWithWrongDirectionFails() throws {
        let plaintext = Data("hello".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 1)
        XCTAssertThrowsError(
            try SecureFrame.open(ct, key: key, prefix: FrameDirection.hostToClient, seq: 1),
            "Falsches Richtungspräfix ⇒ AEAD schlägt fehl")
    }

    func testTamperedCiphertextFails() throws {
        let plaintext = Data("sensitive".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 0)
        // Ein Byte im Ciphertext kippen (über ein 0-basiertes Byte-Array, damit
        // der Test unabhängig von der internen Data-Indexbasis ist).
        var bytes = [UInt8](ct)
        bytes[0] ^= 0xFF
        XCTAssertThrowsError(
            try SecureFrame.open(Data(bytes), key: key, prefix: FrameDirection.clientToHost, seq: 0))
    }

    func testTamperedTagFails() throws {
        let plaintext = Data("sensitive".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 0)
        var bytes = [UInt8](ct)
        bytes[bytes.count - 1] ^= 0x01
        XCTAssertThrowsError(
            try SecureFrame.open(Data(bytes), key: key, prefix: FrameDirection.clientToHost, seq: 0))
    }

    func testTooShortInputThrows() {
        XCTAssertThrowsError(
            try SecureFrame.open(Data([0x00, 0x01]), key: key, prefix: FrameDirection.clientToHost, seq: 0))
    }

    func testWrongKeyFails() throws {
        let plaintext = Data("hello".utf8)
        let ct = try SecureFrame.seal(plaintext, key: key, prefix: FrameDirection.clientToHost, seq: 5)
        let otherKey = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(
            try SecureFrame.open(ct, key: otherKey, prefix: FrameDirection.clientToHost, seq: 5))
    }

    /// Bildet den Replay-Schutz (streng monoton steigende seq) als reine Logik ab:
    /// Ein Frame mit seq ≤ letzter empfangener seq muss verworfen werden.
    func testMonotonicSeqReplayLogic() {
        func accept(_ seq: UInt64, last: UInt64?) -> Bool {
            if let last, seq <= last { return false }
            return true
        }
        XCTAssertTrue(accept(0, last: nil))
        XCTAssertTrue(accept(1, last: 0))
        XCTAssertFalse(accept(0, last: 0))   // Replay derselben seq
        XCTAssertFalse(accept(5, last: 9))   // Rückwärts
        XCTAssertTrue(accept(10, last: 9))
    }
}
