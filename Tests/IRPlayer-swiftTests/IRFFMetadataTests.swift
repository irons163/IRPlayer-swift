//
//  IRFFMetadataTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import XCTest
@testable import IRPlayer_swift

final class IRFFMetadataTests: XCTestCase {

    func testMetadataWithNilAVDictionaryUsesEmptyDefaults() {
        let metadata = IRFFMetadata(avDictionary: nil)

        XCTAssertEqual(metadata.language, "")
        XCTAssertEqual(metadata.BPS, 0)
        XCTAssertEqual(metadata.duration, "")
        XCTAssertEqual(metadata.numberOfBytes, 0)
        XCTAssertEqual(metadata.numberOfFrames, 0)
    }

    func testMetadataParsesStringValuesFromDictionary() {
        let metadata = IRFFMetadata(dictionary: [
            "language": "en",
            "BPS": "192000",
            "DURATION": "00:00:10.000",
            "NUMBER_OF_BYTES": "240000",
            "NUMBER_OF_FRAMES": "300"
        ])

        XCTAssertEqual(metadata.language, "en")
        XCTAssertEqual(metadata.BPS, 192000)
        XCTAssertEqual(metadata.duration, "00:00:10.000")
        XCTAssertEqual(metadata.numberOfBytes, 240000)
        XCTAssertEqual(metadata.numberOfFrames, 300)
    }

    func testMetadataDefaultsMissingAndMalformedNumericValues() {
        let metadata = IRFFMetadata(dictionary: ["BPS": "not-a-number"])

        XCTAssertEqual(metadata.language, "")
        XCTAssertEqual(metadata.BPS, 0)
        XCTAssertEqual(metadata.duration, "")
        XCTAssertEqual(metadata.numberOfBytes, 0)
        XCTAssertEqual(metadata.numberOfFrames, 0)
    }

    func testMetadataParsesNumericStringsWithSurroundingWhitespace() {
        let metadata = IRFFMetadata(dictionary: [
            "BPS": " 192000 ",
            "NUMBER_OF_BYTES": "\t240000\n",
            "NUMBER_OF_FRAMES": " 300"
        ])

        XCTAssertEqual(metadata.BPS, 192000)
        XCTAssertEqual(metadata.numberOfBytes, 240000)
        XCTAssertEqual(metadata.numberOfFrames, 300)
    }

    func testMetadataDefaultsMalformedNumericObjects() {
        XCTAssertEqual(IRFFMetadata.int64Value(NSNumber(value: true)), 0)
        XCTAssertEqual(IRFFMetadata.int64Value(NSNumber(value: 12.5)), 0)
        XCTAssertEqual(IRFFMetadata.int64Value(NSNumber(value: Double.nan)), 0)
        XCTAssertEqual(IRFFMetadata.int64Value(NSNumber(value: Double.infinity)), 0)
    }

    func testMetadataIsAnEquatableImmutableValue() {
        let first = IRFFMetadata(
            dictionary: [
                "language": "eng",
                "BPS": "192000"
            ]
        )
        let second = IRFFMetadata(
            dictionary: [
                "language": "eng",
                "BPS": "192000"
            ]
        )

        XCTAssertEqual(first, second)
    }

    func testInt64ValueAcceptsIntegralBoundsAndRejectsOverflow() {
        XCTAssertEqual(
            IRFFMetadata.int64Value("\(Int64.min)"),
            Int64.min
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value("\(Int64.max)"),
            Int64.max
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value(
                "9223372036854775808"
            ),
            0
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value(
                NSNumber(value: Int64.min)
            ),
            Int64.min
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value(
                NSNumber(value: Int64.max)
            ),
            Int64.max
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value(
                NSNumber(value: UInt64.max)
            ),
            0
        )
        XCTAssertEqual(
            IRFFMetadata.int64Value(
                NSNumber(
                    value:
                        9_223_372_036_854_775_808.0
                )
            ),
            0
        )
        XCTAssertEqual(IRFFMetadata.int64Value(nil), 0)
    }
}
