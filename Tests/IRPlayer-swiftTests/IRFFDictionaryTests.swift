import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDictionaryTests: XCTestCase {
    func testBorrowedValuesReturnNilForMissingDictionary() {
        XCTAssertNil(
            IRFFDictionary.values(from: nil)
        )
    }

    func testOwnerCreationRejectsEmptyEntries() {
        XCTAssertNil(
            IRFFDictionary(entries: [])
        )
    }

    func testOwnerCreatesAndReplacesRealDictionaryEntries() throws {
        let dictionary = try XCTUnwrap(
            IRFFDictionary(
                entries: [
                    (key: "language", value: "eng"),
                    (key: "title", value: "Camera 1")
                ]
            )
        )

        XCTAssertTrue(
            dictionary.set(
                key: "title",
                value: "Camera 2"
            )
        )
        XCTAssertEqual(dictionary.values["language"], "eng")
        XCTAssertEqual(dictionary.values["title"], "Camera 2")
        XCTAssertEqual(
            dictionary.diagnostics,
            .init(
                closed: false,
                hasRawPointer: true,
                entryCount: 2
            )
        )
    }

    func testScopedRawBorrowExposesOwnedPointerAndReturnsResult() {
        let dictionary = IRFFDictionary(
            entries: [(key: "transport", value: "tcp")]
        )!
        var didRun = false

        let result = dictionary.withMutableRawPointer {
            pointer in
            didRun = true
            return pointer == nil ? -1 : 17
        }

        XCTAssertTrue(didRun)
        XCTAssertEqual(result, 17)
        XCTAssertEqual(dictionary.values["transport"], "tcp")
    }

    func testCloseIsIdempotentAndRejectsLaterMutation() {
        let dictionary = IRFFDictionary(
            entries: [(key: "language", value: "eng")]
        )!

        dictionary.close()
        dictionary.close()

        XCTAssertEqual(
            dictionary.diagnostics,
            .init(
                closed: true,
                hasRawPointer: false,
                entryCount: 0
            )
        )
        XCTAssertFalse(
            dictionary.set(
                key: "title",
                value: "closed"
            )
        )
        XCTAssertEqual(
            dictionary.withMutableRawPointer { _ in 0 },
            -1
        )
    }

    func testOwnerDeinitializesWithoutExternalCleanup() {
        weak var weakDictionary: IRFFDictionary?

        autoreleasepool {
            let dictionary = IRFFDictionary(
                entries: [(key: "language", value: "eng")]
            )
            weakDictionary = dictionary
            XCTAssertNotNil(weakDictionary)
        }

        XCTAssertNil(weakDictionary)
    }

    func testCStringDecodingRejectsMissingAndMalformedUTF8() throws {
        XCTAssertNil(
            IRFFDictionary.string(fromCString: nil)
        )

        let invalidValue: [CChar] = [-1, 0]
        try invalidValue.withUnsafeBufferPointer { buffer in
            let value = try XCTUnwrap(buffer.baseAddress)
            XCTAssertNil(
                IRFFDictionary.string(
                    fromCString: value
                )
            )
        }
    }

    func testCStringDecodingReturnsValidUTF8() {
        "Camera 1".withCString { value in
            XCTAssertEqual(
                IRFFDictionary.string(
                    fromCString: value
                ),
                "Camera 1"
            )
        }
    }

    func testBorrowedEntriesSkipMalformedPairs() throws {
        let invalidValue: [CChar] = [-1, 0]

        try invalidValue.withUnsafeBufferPointer {
            invalidBuffer in
            let invalidCString = try XCTUnwrap(
                invalidBuffer.baseAddress
            )
            "language".withCString { languageKey in
                "eng".withCString { languageValue in
                    "title".withCString { titleKey in
                        let values = IRFFDictionary.values(
                            entries: [
                                (
                                    key: languageKey,
                                    value: languageValue
                                ),
                                (
                                    key: titleKey,
                                    value: invalidCString
                                )
                            ]
                        )

                        XCTAssertEqual(
                            values,
                            ["language": "eng"]
                        )
                    }
                }
            }
        }
    }
}
