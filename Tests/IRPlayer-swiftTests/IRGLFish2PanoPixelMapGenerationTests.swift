import XCTest
@testable import IRPlayer_swift

final class IRGLFish2PanoPixelMapGenerationTests:
    XCTestCase
{
    func testCompleteGenerationPublishesCoherentDiagnostics()
        throws
    {
        let generation = try XCTUnwrap(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 7,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 2,
                maps: [
                    [0, 1, 2, 3],
                    [4, 5, 6, 7],
                    [8, 9, 10, 11],
                    [12, 13, 14, 15]
                ]
            )
        )

        XCTAssertEqual(
            generation.diagnostics,
            IRGLFish2PanoPixelMapDiagnostics(
                requestGeneration: 7,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 2,
                textureCount: 4,
                elementCountPerTexture: 4
            )
        )
        XCTAssertEqual(
            generation.withUnsafeMapBuffer(at: 2) {
                Array($0)
            },
            [8, 9, 10, 11]
        )
        XCTAssertNil(
            generation.withUnsafeMapBuffer(at: -1) {
                $0.count
            }
        )
        XCTAssertNil(
            generation.withUnsafeMapBuffer(at: 4) {
                $0.count
            }
        )
    }

    func testGenerationRejectsIncompleteLayouts() {
        let validMap: [GLfloat] = [0, 1, 2, 3]

        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 0,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 1,
                maps: [validMap]
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 1,
                outputWidth: 0,
                outputHeight: 1,
                antialias: 1,
                maps: [validMap]
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 1,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 2,
                maps: [validMap]
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 1,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 1,
                maps: [[0, 1]]
            )
        )
    }

    func testGenerationIsImmutableAfterSourceMutation()
        throws
    {
        var maps: [[GLfloat]] = [[0, 1, 2, 3]]
        let generation = try XCTUnwrap(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 1,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 1,
                maps: maps
            )
        )

        maps[0][0] = 99

        XCTAssertEqual(
            generation.withUnsafeMapBuffer(at: 0) {
                $0[0]
            },
            0
        )
    }

    func testLayoutValidationUsesCheckedArithmetic() {
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration.outputSize(
                forTextureWidth: Int.max,
                height: 1
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration.textureCount(
                antialias: Int.max
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration.elementCount(
                outputWidth: Int.max,
                outputHeight: 2
            )
        )
        XCTAssertNil(
            IRGLFish2PanoPixelMapGeneration.uvOffset(
                outputWidth: 2,
                outputHeight: 1,
                x: 2,
                y: 0
            )
        )
        XCTAssertEqual(
            IRGLFish2PanoPixelMapGeneration.uvOffset(
                outputWidth: 2,
                outputHeight: 1,
                x: 1,
                y: 0
            ),
            2
        )
    }

    func testConcurrentScopedReadsRemainCoherent() throws {
        let generation = try XCTUnwrap(
            IRGLFish2PanoPixelMapGeneration(
                requestGeneration: 1,
                outputWidth: 2,
                outputHeight: 1,
                antialias: 1,
                maps: [[1, 2, 3, 4]]
            )
        )
        let sums = LockedDecoderResourceValue<[GLfloat]>([])

        DispatchQueue.concurrentPerform(iterations: 100) {
            _ in
            let sum = generation.withUnsafeMapBuffer(at: 0) {
                $0.reduce(0, +)
            }
            sums.withValue {
                $0.append(sum ?? -1)
            }
        }

        XCTAssertEqual(sums.value.count, 100)
        XCTAssertTrue(sums.value.allSatisfy {
            $0 == 10
        })
    }
}
