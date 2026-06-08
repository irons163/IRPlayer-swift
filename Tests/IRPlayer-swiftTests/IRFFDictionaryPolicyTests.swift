import XCTest
@testable import IRPlayer_swift

final class IRFFDictionaryPolicyTests: XCTestCase {

    func testFoundationDictionaryReturnsNilForMissingDictionary() {
        XCTAssertNil(IRFFDictionaryPolicy.foundationDictionary(from: nil))
    }
}
