import Metal
import XCTest
@testable import IRPlayer_swift

final class IRMetalCommandResourcesTests: XCTestCase {
    private final class Token {}

    func testNewScopeStartsEmptyAndCollecting() {
        let resources = IRMetalCommandResources()

        XCTAssertEqual(
            resources.diagnostics,
            IRMetalCommandResourceDiagnostics(
                state: .collecting,
                cachedFrameCount: 0,
                additionalResourceCount: 0
            )
        )
    }

    func testFrameGenerationIsCachedByFrameIdentity() throws {
        let generation = try makeGeneration()
        let resources = IRMetalCommandResources()
        let firstFrame = IRFFVideoFrame()
        let secondFrame = IRFFVideoFrame()
        var makeCount = 0

        let first = resources.frameTextureGeneration(
            for: firstFrame
        ) {
            makeCount += 1
            return generation
        }
        let repeated = resources.frameTextureGeneration(
            for: firstFrame
        ) {
            makeCount += 1
            return generation
        }
        let second = resources.frameTextureGeneration(
            for: secondFrame
        ) {
            makeCount += 1
            return generation
        }

        XCTAssertTrue(first === generation)
        XCTAssertTrue(repeated === generation)
        XCTAssertTrue(second === generation)
        XCTAssertEqual(makeCount, 2)
        XCTAssertEqual(
            resources.diagnostics.cachedFrameCount,
            2
        )
    }

    func testFailedFrameGenerationIsNotCached() {
        let resources = IRMetalCommandResources()
        let frame = IRFFVideoFrame()
        var makeCount = 0

        XCTAssertNil(
            resources.frameTextureGeneration(for: frame) {
                makeCount += 1
                return nil
            }
        )
        XCTAssertNil(
            resources.frameTextureGeneration(for: frame) {
                makeCount += 1
                return nil
            }
        )

        XCTAssertEqual(makeCount, 2)
        XCTAssertEqual(
            resources.diagnostics.cachedFrameCount,
            0
        )
    }

    func testSubmissionRetainsUntilCompletionThenReleases() {
        let resources = IRMetalCommandResources()
        weak var weakToken: Token?
        var completion: (@Sendable () -> Void)?

        autoreleasepool {
            var token: Token? = Token()
            weakToken = token
            XCTAssertTrue(resources.retain(token!))
            token = nil
            XCTAssertNotNil(weakToken)

            XCTAssertTrue(
                resources.submit { registeredCompletion in
                    completion = registeredCompletion
                }
            )
            XCTAssertNotNil(weakToken)
            XCTAssertEqual(
                resources.diagnostics,
                IRMetalCommandResourceDiagnostics(
                    state: .submitted,
                    cachedFrameCount: 0,
                    additionalResourceCount: 0
                )
            )

            completion?()
        }

        XCTAssertNil(weakToken)
        completion?()
        XCTAssertNil(weakToken)
    }

    func testSubmissionAndCancellationAreTerminal() {
        let submitted = IRMetalCommandResources()
        XCTAssertTrue(submitted.submit { completion in
            completion()
        })
        XCTAssertFalse(submitted.retain(Token()))
        XCTAssertFalse(submitted.submit { _ in })
        XCTAssertFalse(submitted.cancel())

        let cancelled = IRMetalCommandResources()
        XCTAssertTrue(cancelled.cancel())
        XCTAssertFalse(cancelled.cancel())
        XCTAssertFalse(cancelled.retain(Token()))
        XCTAssertFalse(cancelled.submit { _ in })
        XCTAssertEqual(
            cancelled.diagnostics.state,
            .cancelled
        )
    }

    func testCancellationAndDeinitReleaseCollectedResources() {
        weak var cancelledToken: Token?
        let cancelled = IRMetalCommandResources()
        autoreleasepool {
            var token: Token? = Token()
            cancelledToken = token
            XCTAssertTrue(cancelled.retain(token!))
            token = nil
            XCTAssertNotNil(cancelledToken)
            XCTAssertTrue(cancelled.cancel())
        }
        XCTAssertNil(cancelledToken)

        weak var deinitToken: Token?
        autoreleasepool {
            let resources = IRMetalCommandResources()
            var token: Token? = Token()
            deinitToken = token
            XCTAssertTrue(resources.retain(token!))
            token = nil
            XCTAssertNotNil(deinitToken)
        }
        XCTAssertNil(deinitToken)
    }

    func testSubmissionWaitsForActiveGenerationConstruction() throws {
        let generation = try makeGeneration()
        let resources = IRMetalCommandResources()
        let frame = IRFFVideoFrame()
        let constructionStarted = DispatchSemaphore(value: 0)
        let allowConstruction = DispatchSemaphore(value: 0)
        let constructionFinished = DispatchSemaphore(value: 0)
        let submissionFinished = DispatchSemaphore(value: 0)
        let submitted =
            LockedDecoderResourceValue<Bool?>(nil)

        DispatchQueue.global().async {
            _ = resources.frameTextureGeneration(for: frame) {
                constructionStarted.signal()
                _ = allowConstruction.wait(
                    timeout: .now() + 2
                )
                return generation
            }
            constructionFinished.signal()
        }
        XCTAssertEqual(
            constructionStarted.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            let result = resources.submit { completion in
                completion()
            }
            submitted.withValue {
                $0 = result
            }
            submissionFinished.signal()
        }
        XCTAssertEqual(
            submissionFinished.wait(
                timeout: .now() + 0.05
            ),
            .timedOut
        )

        allowConstruction.signal()
        XCTAssertEqual(
            constructionFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            submissionFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(submitted.value, true)
        XCTAssertEqual(
            resources.diagnostics.state,
            .submitted
        )
    }

    func testRealCommandBufferCompletionReleasesResources() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw XCTSkip("Metal command buffer unavailable")
        }

        let resources = IRMetalCommandResources()
        weak var weakToken: Token?
        autoreleasepool {
            var token: Token? = Token()
            weakToken = token
            XCTAssertTrue(resources.retain(token!))
            token = nil
        }

        XCTAssertNotNil(weakToken)
        XCTAssertTrue(resources.submit(to: commandBuffer))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(weakToken)
    }

    private func makeGeneration()
        throws -> IRMetalFrameTextureGeneration
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let descriptor =
            MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 1,
                height: 1,
                mipmapped: false
            )
        guard let texture =
                device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Metal texture unavailable")
        }
        return IRMetalFrameTextureGeneration(
            textures: .rgb(texture)
        )
    }
}
