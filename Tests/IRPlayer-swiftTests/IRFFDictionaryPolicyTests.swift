import XCTest
@testable import IRPlayer_swift

final class IRFFDictionaryPolicyTests: XCTestCase {

    func testFoundationDictionaryReturnsNilForMissingDictionary() {
        XCTAssertNil(IRFFDictionaryPolicy.foundationDictionary(from: nil))
    }

    func testCStringDecodingRejectsMissingAndMalformedUTF8Pointers() throws {
        XCTAssertNil(IRFFDictionaryPolicy.string(fromCString: nil))

        let invalidValue: [CChar] = [-1, 0]
        try invalidValue.withUnsafeBufferPointer { buffer in
            let value = try XCTUnwrap(buffer.baseAddress)
            XCTAssertNil(IRFFDictionaryPolicy.string(fromCString: value))
        }
    }

    func testCStringDecodingReturnsValidUTF8Strings() throws {
        try "Camera 1".withCString { value in
            XCTAssertEqual(IRFFDictionaryPolicy.string(fromCString: value), "Camera 1")
        }
    }
}
