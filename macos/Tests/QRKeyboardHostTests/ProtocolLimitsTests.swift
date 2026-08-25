import XCTest
@testable import QRKeyboardHost

/// Tests der reinen Grenz-/Mapping-Logik: Payload-Längenlimit (UTF-16) und
/// Tippgeschwindigkeit (Chunk-Größe/Pause).
final class ProtocolLimitsTests: XCTestCase {

    // MARK: - payload_too_large (8192 UTF-16)

    func testTextAtLimitIsAllowed() {
        let text = String(repeating: "a", count: ScanServer.maximumTextLength)
        XCTAssertEqual(text.utf16.count, 8192)
        XCTAssertTrue(ScanServer.isTextWithinLimit(text))
    }

    func testTextOverLimitIsRejected() {
        let text = String(repeating: "a", count: ScanServer.maximumTextLength + 1)
        XCTAssertFalse(ScanServer.isTextWithinLimit(text))
    }

    func testEmptyTextIsAllowed() {
        XCTAssertTrue(ScanServer.isTextWithinLimit(""))
    }

    /// Das Limit zählt UTF-16-Einheiten: ein Emoji außerhalb der BMP ist ein
    /// Surrogatpaar (2 Einheiten). 4096 Emoji = 8192 Einheiten (erlaubt),
    /// 4097 = 8194 (abgelehnt).
    func testSurrogatePairsCountAsTwoUTF16Units() {
        let emoji = "😀" // U+1F600 ⇒ 2 UTF-16-Einheiten
        XCTAssertEqual(emoji.utf16.count, 2)

        let atLimit = String(repeating: emoji, count: 4096)
        XCTAssertEqual(atLimit.utf16.count, 8192)
        XCTAssertTrue(ScanServer.isTextWithinLimit(atLimit))

        let overLimit = String(repeating: emoji, count: 4097)
        XCTAssertEqual(overLimit.utf16.count, 8194)
        XCTAssertFalse(ScanServer.isTextWithinLimit(overLimit))
    }

    // MARK: - TypingSpeed-Mapping

    func testTypingSpeedRawValuesAndCases() {
        XCTAssertEqual(TypingSpeed.allCases, [.fast, .normal, .slow])
        XCTAssertEqual(TypingSpeed.fast.rawValue, "fast")
        XCTAssertEqual(TypingSpeed.normal.rawValue, "normal")
        XCTAssertEqual(TypingSpeed.slow.rawValue, "slow")
    }

    func testTypingSpeedChunkSizeMapping() {
        XCTAssertEqual(TypingSpeed.fast.chunkSize, 40)
        XCTAssertEqual(TypingSpeed.normal.chunkSize, 20)
        XCTAssertEqual(TypingSpeed.slow.chunkSize, 8)
        // Monoton: schneller ⇒ größere Chunks.
        XCTAssertGreaterThan(TypingSpeed.fast.chunkSize, TypingSpeed.normal.chunkSize)
        XCTAssertGreaterThan(TypingSpeed.normal.chunkSize, TypingSpeed.slow.chunkSize)
    }

    func testTypingSpeedDelayMapping() {
        XCTAssertEqual(TypingSpeed.fast.interChunkDelayMicroseconds, 3_000)
        XCTAssertEqual(TypingSpeed.normal.interChunkDelayMicroseconds, 10_000)
        XCTAssertEqual(TypingSpeed.slow.interChunkDelayMicroseconds, 32_000)
        // Monoton: langsamer ⇒ größere Pause.
        XCTAssertLessThan(TypingSpeed.fast.interChunkDelayMicroseconds,
                          TypingSpeed.normal.interChunkDelayMicroseconds)
        XCTAssertLessThan(TypingSpeed.normal.interChunkDelayMicroseconds,
                          TypingSpeed.slow.interChunkDelayMicroseconds)
    }

    func testTypingSpeedDefaultsToNormalForUnknownRawValue() {
        XCTAssertNil(TypingSpeed(rawValue: "bogus"))
    }
}
