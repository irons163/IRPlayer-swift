import XCTest
@testable import IRPlayer_swift

final class IRMetalMeshStorageTests: XCTestCase {

    func testByteLengthRejectsZeroElementCount() {
        XCTAssertNil(
            IRMetalMeshStorage.byteLength(
                elementCount: 0,
                stride: 4
            )
        )
    }

    func testByteLengthRejectsNegativeElementCount() {
        XCTAssertNil(
            IRMetalMeshStorage.byteLength(
                elementCount: -1,
                stride: 4
            )
        )
    }

    func testByteLengthRejectsZeroStride() {
        XCTAssertNil(
            IRMetalMeshStorage.byteLength(
                elementCount: 1,
                stride: 0
            )
        )
    }

    func testByteLengthRejectsNegativeStride() {
        XCTAssertNil(
            IRMetalMeshStorage.byteLength(
                elementCount: 1,
                stride: -1
            )
        )
    }

    func testByteLengthRejectsMultiplicationOverflow() {
        XCTAssertNil(
            IRMetalMeshStorage.byteLength(
                elementCount: Int.max,
                stride: 2
            )
        )
    }

    func testByteLengthCalculatesExactStorage() {
        XCTAssertEqual(
            IRMetalMeshStorage.byteLength(
                elementCount: 4,
                stride: MemoryLayout<UInt16>.stride
            ),
            8
        )
    }

    func testByteLengthSupportsUnitStride() {
        XCTAssertEqual(
            IRMetalMeshStorage.byteLength(
                elementCount: Int.max,
                stride: 1
            ),
            Int.max
        )
    }

    func testIndexRejectsNegativeValue() {
        XCTAssertNil(IRMetalMeshStorage.index(-1))
    }

    func testIndexRejectsValueAboveUInt16Range() {
        XCTAssertNil(
            IRMetalMeshStorage.index(
                Int(UInt16.max) + 1
            )
        )
    }

    func testIndexConvertsZero() {
        XCTAssertEqual(IRMetalMeshStorage.index(0), 0)
    }

    func testIndexConvertsUInt16Maximum() {
        XCTAssertEqual(
            IRMetalMeshStorage.index(Int(UInt16.max)),
            UInt16.max
        )
    }

    func testIndexConvertsIntermediateValueExactly() {
        XCTAssertEqual(
            IRMetalMeshStorage.index(32_768),
            32_768
        )
    }
}
