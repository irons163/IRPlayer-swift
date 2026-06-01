//
//  IRFFMetadataTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import XCTest
@testable import IRPlayer_swift

final class IRFFMetadataTests: XCTestCase {

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
}
