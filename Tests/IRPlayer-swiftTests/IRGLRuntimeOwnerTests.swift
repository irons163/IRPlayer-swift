import AVFoundation
import CoreImage
import Metal
import QuartzCore
import XCTest
@testable import IRPlayer_swift

private final class IRGLOwnerCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private final class IRGLDeferredDispatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [() -> Void] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return operations.count
    }

    func dispatch(_ operation: @escaping () -> Void) {
        lock.lock()
        operations.append(operation)
        lock.unlock()
    }

    func runAll() {
        lock.lock()
        let pending = operations
        operations.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }
}

private final class IRGLOwnerFrameRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrameIdentifiers: [ObjectIdentifier?] = []
    private var storedImagePresence: [Bool] = []

    var frameIdentifiers: [ObjectIdentifier?] {
        lock.lock()
        defer { lock.unlock() }
        return storedFrameIdentifiers
    }

    var imagePresence: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedImagePresence
    }

    func record(_ input: IRGLFrameSubmissionSession.RenderInput) {
        lock.lock()
        storedFrameIdentifiers.append(
            input.currentFrame.map(ObjectIdentifier.init)
        )
        storedImagePresence.append(input.currentImage != nil)
        lock.unlock()
    }
}

private final class IRGLOwnerIntRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: Int) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

final class IRGLRenderExecutorTests: XCTestCase {
    func testSyncIsReentrantWithoutDeadlock() {
        let executor = IRGLRenderExecutor(
            label: "IRGLRenderExecutorTests.reentrant"
        )
        var observedCurrentExecutor = false

        executor.sync {
            XCTAssertTrue(executor.isCurrentExecutor)
            executor.sync {
                observedCurrentExecutor = executor.isCurrentExecutor
            }
        }

        XCTAssertTrue(observedCurrentExecutor)
        XCTAssertEqual(executor.diagnostics.entryCount, 2)
        XCTAssertEqual(executor.diagnostics.queuedEntryCount, 1)
        XCTAssertEqual(executor.diagnostics.reentrantEntryCount, 1)
    }

    func testConcurrentSyncCallsAreSerialized() {
        let executor = IRGLRenderExecutor(
            label: "IRGLRenderExecutorTests.serial"
        )
        var values: [Int] = []

        DispatchQueue.concurrentPerform(iterations: 100) { value in
            executor.sync {
                values.append(value)
            }
        }

        XCTAssertEqual(values.count, 100)
        XCTAssertEqual(Set(values), Set(0..<100))
        XCTAssertEqual(executor.diagnostics.queuedEntryCount, 100)
    }

    func testAsyncOperationsPreserveSubmissionOrder() {
        let executor = IRGLRenderExecutor(
            label: "IRGLRenderExecutorTests.async"
        )
        let completed = expectation(description: "async operations")
        let values = IRGLOwnerIntRecorder()

        for value in 0..<10 {
            executor.async {
                values.append(value)
                if value == 9 {
                    completed.fulfill()
                }
            }
        }

        wait(for: [completed], timeout: 1)
        executor.sync {}
        XCTAssertEqual(values.values, Array(0..<10))
        XCTAssertEqual(executor.diagnostics.entryCount, 11)
    }
}

final class IRGLMetalSurfaceSessionTests: XCTestCase {
    private func makeInput(
        layer: CAMetalLayer = CAMetalLayer(),
        bounds: CGRect = CGRect(x: 0, y: 0, width: 100, height: 50),
        screenScale: CGFloat = 2,
        viewportScale: CGFloat = 1
    ) -> IRGLMetalSurfaceSession.Input {
        IRGLMetalSurfaceSession.Input(
            layer: layer,
            bounds: bounds,
            screenScale: screenScale,
            viewportScale: viewportScale
        )
    }

    func testPreparePublishesNoPartialResourcesWhenDeviceIsMissing() {
        let executor = IRGLRenderExecutor()
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        let session = IRGLMetalSurfaceSession(
            executor: executor,
            dependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { nil },
                makeCommandQueue: { _ in nil },
                makeCIContext: { _ in nil },
                makeRenderer: {
                    _,
                    _ in .failure(.missingShaderLibrary)
                }
            )
        )

        XCTAssertFalse(session.prepare(makeInput(layer: layer)))
        XCTAssertEqual(
            session.diagnostics.phase,
            .unavailable(.missingDevice)
        )
        XCTAssertFalse(session.diagnostics.hasCompleteResources)
        XCTAssertNil(session.resourceSnapshot)
        XCTAssertNil(layer.device)
    }

    func testPrepareReportsExactFactoryFailure() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor(),
            dependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { device },
                makeCommandQueue: { _ in nil },
                makeCIContext: { _ in nil },
                makeRenderer: {
                    _,
                    _ in .failure(.missingShaderLibrary)
                }
            )
        )

        XCTAssertFalse(session.prepare(makeInput()))
        XCTAssertEqual(
            session.diagnostics.phase,
            .unavailable(.missingCommandQueue)
        )
        XCTAssertFalse(session.diagnostics.hasCompleteResources)
    }

    func testPrepareReportsExactRendererFailureWithoutPublication()
        throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let layer = CAMetalLayer()
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor(),
            dependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { device },
                makeCommandQueue: { $0.makeCommandQueue() },
                makeCIContext: { CIContext(mtlDevice: $0) },
                makeRenderer: { _, _ in
                    .failure(
                        .missingShaderFunction("irVertex3D")
                    )
                }
            )
        )

        XCTAssertFalse(session.prepare(makeInput(layer: layer)))
        XCTAssertEqual(
            session.diagnostics.phase,
            .unavailable(
                .renderer(
                    .missingShaderFunction("irVertex3D")
                )
            )
        )
        XCTAssertNil(session.resourceSnapshot)
        XCTAssertNil(layer.device)
    }

    func testPrepareReportsMissingCIContextBeforeRenderer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        var rendererCallCount = 0
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor(),
            dependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { device },
                makeCommandQueue: { $0.makeCommandQueue() },
                makeCIContext: { _ in nil },
                makeRenderer: { _, _ in
                    rendererCallCount += 1
                    return .failure(.missingShaderLibrary)
                }
            )
        )

        XCTAssertFalse(session.prepare(makeInput()))
        XCTAssertEqual(
            session.diagnostics.phase,
            .unavailable(.missingCIContext)
        )
        XCTAssertEqual(rendererCallCount, 0)
        XCTAssertNil(session.resourceSnapshot)
    }

    func testRendererFailureCanRetryWithCompleteSharedQueue()
        throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        var rendererAttemptCount = 0
        let layer = CAMetalLayer()
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor(),
            dependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { device },
                makeCommandQueue: { $0.makeCommandQueue() },
                makeCIContext: { CIContext(mtlDevice: $0) },
                makeRenderer: { device, commandQueue in
                    rendererAttemptCount += 1
                    guard rendererAttemptCount > 1 else {
                        return .failure(.missingShaderLibrary)
                    }
                    return IRMetalRenderer.make(
                        device: device,
                        commandQueue: commandQueue
                    )
                }
            )
        )

        XCTAssertFalse(session.prepare(makeInput(layer: layer)))
        XCTAssertEqual(
            session.diagnostics.phase,
            .unavailable(
                .renderer(.missingShaderLibrary)
            )
        )

        XCTAssertTrue(session.prepare(makeInput(layer: layer)))
        let resources = try XCTUnwrap(session.resourceSnapshot)
        XCTAssertEqual(rendererAttemptCount, 2)
        XCTAssertEqual(session.diagnostics.generation, 1)
        XCTAssertTrue(
            resources.commandQueue ===
                resources.renderer.commandQueue
        )
    }

    func testPrepareResizeResetAndCloseOwnCompleteGeneration() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let layer = CAMetalLayer()
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor()
        )

        XCTAssertTrue(session.prepare(makeInput(layer: layer)))
        XCTAssertEqual(session.diagnostics.phase, .ready)
        XCTAssertEqual(session.diagnostics.generation, 1)
        XCTAssertEqual(session.diagnostics.pixelWidth, 200)
        XCTAssertEqual(session.diagnostics.pixelHeight, 100)
        XCTAssertTrue(session.diagnostics.hasCompleteResources)
        XCTAssertNotNil(layer.device)
        let resources = try XCTUnwrap(session.resourceSnapshot)
        XCTAssertTrue(
            resources.commandQueue ===
                resources.renderer.commandQueue
        )
        XCTAssertEqual(
            resources.renderer.resources.diagnostics.pipelineCount,
            10
        )

        XCTAssertTrue(
            session.resize(
                makeInput(
                    layer: layer,
                    bounds: CGRect(
                        x: 0,
                        y: 0,
                        width: 60,
                        height: 40
                    ),
                    viewportScale: 0.5
                )
            )
        )
        XCTAssertEqual(session.diagnostics.pixelWidth, 60)
        XCTAssertEqual(session.diagnostics.pixelHeight, 40)

        session.reset()
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertFalse(session.diagnostics.hasCompleteResources)
        XCTAssertNil(layer.device)

        XCTAssertTrue(session.prepare(makeInput(layer: layer)))
        XCTAssertEqual(session.diagnostics.generation, 2)
        XCTAssertTrue(session.close())
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertNil(layer.device)
        XCTAssertFalse(session.close())
        XCTAssertFalse(session.prepare(makeInput(layer: layer)))
    }

    func testInvalidResizePreservesLastValidPixelSize() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let layer = CAMetalLayer()
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor()
        )
        XCTAssertTrue(session.prepare(makeInput(layer: layer)))

        XCTAssertFalse(
            session.resize(
                makeInput(
                    layer: layer,
                    bounds: CGRect(
                        x: 0,
                        y: 0,
                        width: CGFloat.nan,
                        height: 10
                    )
                )
            )
        )
        XCTAssertEqual(session.diagnostics.pixelWidth, 200)
        XCTAssertEqual(session.diagnostics.pixelHeight, 100)
        XCTAssertEqual(session.diagnostics.rejectedOperationCount, 1)
    }

    func testResizeRejectsAReplacementLayer() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let session = IRGLMetalSurfaceSession(
            executor: IRGLRenderExecutor()
        )
        XCTAssertTrue(session.prepare(makeInput()))

        XCTAssertFalse(session.resize(makeInput(layer: CAMetalLayer())))
        XCTAssertEqual(session.diagnostics.rejectedOperationCount, 1)
    }

    func testPixelSizeRejectsInvalidScaleAndOverflow() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

        XCTAssertNil(
            IRGLMetalSurfaceSession.pixelSize(
                bounds: bounds,
                screenScale: 0,
                viewportScale: 1
            )
        )
        XCTAssertNil(
            IRGLMetalSurfaceSession.pixelSize(
                bounds: bounds,
                screenScale: 1,
                viewportScale: .infinity
            )
        )
        XCTAssertNil(
            IRGLMetalSurfaceSession.pixelSize(
                bounds: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(Int.max),
                    height: 1
                ),
                screenScale: 2,
                viewportScale: 1
            )
        )
    }
}

final class IRGLFrameSubmissionSessionTests: XCTestCase {
    private func makeContext(
        surface: IRGLMetalSurfaceSession.Resources? = nil
    ) -> IRGLFrameSubmissionSession.RenderContext {
        IRGLFrameSubmissionSession.RenderContext(
            surface: surface,
            mode: nil,
            contentMode: .scaleAspectFit
        )
    }

    func testSubmitAndRedrawReuseOwnedFrame() {
        let executor = IRGLRenderExecutor()
        let recorder = IRGLOwnerFrameRecorder()
        let completed = IRGLOwnerCounter()
        let session = IRGLFrameSubmissionSession(
            executor: executor,
            renderOperation: { input in
                recorder.record(input)
                return .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        session.setCompletionHandler {
            XCTAssertTrue(executor.isCurrentExecutor)
            _ = session.diagnostics
            completed.increment()
        }
        let frame = IRFFVideoFrame()
        frame.width = 320
        frame.height = 180

        XCTAssertTrue(session.submit(frame, context: makeContext()))
        XCTAssertTrue(session.submit(nil, context: makeContext()))

        XCTAssertEqual(
            recorder.frameIdentifiers,
            [
                ObjectIdentifier(frame),
                ObjectIdentifier(frame)
            ]
        )
        XCTAssertEqual(completed.value, 2)
        XCTAssertEqual(session.diagnostics.submissionCount, 1)
        XCTAssertEqual(session.diagnostics.redrawCount, 1)
        XCTAssertEqual(session.diagnostics.lastFrameWidth, 320)
        XCTAssertEqual(session.diagnostics.lastFrameHeight, 180)
    }

    func testIncompleteRenderDoesNotNotifyCompletion() {
        let completed = IRGLOwnerCounter()
        let session = IRGLFrameSubmissionSession(
            executor: IRGLRenderExecutor(),
            renderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: false
                )
            }
        )
        session.setCompletionHandler(completed.increment)

        XCTAssertFalse(
            session.submit(IRFFVideoFrame(), context: makeContext())
        )
        XCTAssertEqual(completed.value, 0)
        XCTAssertEqual(session.diagnostics.incompleteRenderCount, 1)
        XCTAssertEqual(session.diagnostics.completedRenderCount, 0)
    }

    func testClearCreatesBlackImageWhenSurfaceHasDrawableSize() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let executor = IRGLRenderExecutor()
        let surface = IRGLMetalSurfaceSession(executor: executor)
        let layer = CAMetalLayer()
        XCTAssertTrue(
            surface.prepare(
                .init(
                    layer: layer,
                    bounds: CGRect(
                        x: 0,
                        y: 0,
                        width: 20,
                        height: 10
                    ),
                    screenScale: 1
                )
            )
        )
        let resources = try XCTUnwrap(surface.resourceSnapshot)
        let recorder = IRGLOwnerFrameRecorder()
        let session = IRGLFrameSubmissionSession(
            executor: executor,
            renderOperation: { input in
                recorder.record(input)
                return .init(
                    currentImage: input.currentImage,
                    didCompleteRender: input.currentImage != nil
                )
            }
        )

        XCTAssertTrue(
            session.clear(context: makeContext(surface: resources))
        )
        XCTAssertEqual(recorder.imagePresence, [true])
        XCTAssertTrue(session.diagnostics.hasCurrentImage)
        XCTAssertFalse(session.diagnostics.hasCurrentFrame)
        XCTAssertEqual(session.diagnostics.clearCount, 1)
    }

    func testResetClearsFrameImageAndDimensions() {
        let session = IRGLFrameSubmissionSession(
            executor: IRGLRenderExecutor(),
            renderOperation: { input in
                .init(
                    currentImage: CIImage(color: .red),
                    didCompleteRender: true
                )
            }
        )
        let frame = IRFFVideoFrame()
        frame.width = 640
        frame.height = 360
        XCTAssertTrue(session.submit(frame, context: makeContext()))

        session.reset()

        XCTAssertFalse(session.diagnostics.hasCurrentFrame)
        XCTAssertFalse(session.diagnostics.hasCurrentImage)
        XCTAssertEqual(session.diagnostics.lastFrameWidth, 0)
        XCTAssertEqual(session.diagnostics.lastFrameHeight, 0)
        XCTAssertEqual(session.diagnostics.resetCount, 1)
    }

    func testCloseIsTerminalAndIdempotent() {
        let session = IRGLFrameSubmissionSession(
            executor: IRGLRenderExecutor(),
            renderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(
            session.submit(IRFFVideoFrame(), context: makeContext())
        )
        XCTAssertFalse(session.clear(context: makeContext()))
        XCTAssertTrue(session.diagnostics.isClosed)
        XCTAssertEqual(session.diagnostics.rejectedSubmissionCount, 2)
    }

    func testConcurrentSubmissionIsSerialized() {
        let session = IRGLFrameSubmissionSession(
            executor: IRGLRenderExecutor(),
            renderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = session.submit(IRFFVideoFrame(), context: makeContext())
        }

        XCTAssertEqual(session.diagnostics.submissionCount, 100)
        XCTAssertEqual(session.diagnostics.completedRenderCount, 100)
    }
}

final class IRGLSnapshotSessionTests: XCTestCase {
    private func makeSession(
        dispatcher: IRGLDeferredDispatcher,
        saves: IRGLOwnerCounter
    ) -> IRGLSnapshotSession {
        IRGLSnapshotSession(
            dependencies: IRGLSnapshotDependencies(
                dispatchToMain: dispatcher.dispatch,
                saveImage: { _ in saves.increment() }
            )
        )
    }

    func testRequestsCoalesceUntilCompletedRenderSchedulesCapture() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )

        XCTAssertTrue(session.request())
        XCTAssertTrue(session.request())
        XCTAssertTrue(session.hasPendingRequest)
        session.renderDidComplete { UIImage() }

        XCTAssertFalse(session.hasPendingRequest)
        XCTAssertEqual(dispatcher.count, 1)
        XCTAssertEqual(session.diagnostics.requestCount, 2)
        XCTAssertEqual(session.diagnostics.coalescedRequestCount, 1)
        XCTAssertEqual(session.diagnostics.scheduledCaptureCount, 1)
        XCTAssertEqual(saves.value, 0)

        dispatcher.runAll()
        XCTAssertEqual(saves.value, 1)
        XCTAssertEqual(session.diagnostics.savedCaptureCount, 1)
    }

    func testCompletedRenderWithoutRequestDoesNothing() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )

        session.renderDidComplete { UIImage() }

        XCTAssertEqual(dispatcher.count, 0)
        XCTAssertEqual(session.diagnostics.scheduledCaptureCount, 0)
    }

    func testNilCaptureIsNotSaved() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )
        XCTAssertTrue(session.request())
        session.renderDidComplete { nil }

        dispatcher.runAll()

        XCTAssertEqual(saves.value, 0)
        XCTAssertEqual(session.diagnostics.savedCaptureCount, 0)
        XCTAssertEqual(session.diagnostics.scheduledCaptureCount, 1)
    }

    func testCloseCancelsPendingAndScheduledTickets() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )
        XCTAssertTrue(session.request())
        session.renderDidComplete { UIImage() }
        XCTAssertTrue(session.request())

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(session.request())
        dispatcher.runAll()

        XCTAssertEqual(saves.value, 0)
        XCTAssertEqual(session.diagnostics.cancelledCaptureCount, 2)
        XCTAssertTrue(session.diagnostics.isClosed)
        XCTAssertFalse(session.hasPendingRequest)
    }

    func testCancelPendingRequestPreventsScheduling() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )
        XCTAssertTrue(session.request())

        XCTAssertTrue(session.cancelPendingRequest())
        XCTAssertFalse(session.cancelPendingRequest())
        session.renderDidComplete { UIImage() }

        XCTAssertEqual(dispatcher.count, 0)
        XCTAssertEqual(session.diagnostics.cancelledCaptureCount, 1)
    }

    func testConcurrentRequestsCoalesceSafely() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let session = makeSession(
            dispatcher: dispatcher,
            saves: saves
        )

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertTrue(session.request())
        }

        XCTAssertEqual(session.diagnostics.requestCount, 100)
        XCTAssertEqual(session.diagnostics.coalescedRequestCount, 99)
        XCTAssertTrue(session.hasPendingRequest)
    }
}

final class IRGLAVPlayerLayerSessionTests: XCTestCase {
    func testSetPlayerReusesOwnedLayerAndUpdatesPresentation() {
        let session = IRGLAVPlayerLayerSession()
        let hostLayer = CALayer()
        let firstPlayer = AVPlayer()
        let secondPlayer = AVPlayer()

        XCTAssertTrue(
            session.setPlayer(
                firstPlayer,
                hostLayer: hostLayer,
                bounds: CGRect(x: 0, y: 0, width: 100, height: 50),
                gravity: .resizeAspect
            )
        )
        let firstLayer = session.layerSnapshot
        XCTAssertNotNil(firstLayer)
        XCTAssertTrue(firstLayer?.superlayer === hostLayer)

        XCTAssertTrue(
            session.setPlayer(
                secondPlayer,
                hostLayer: hostLayer,
                bounds: CGRect(x: 0, y: 0, width: 200, height: 100),
                gravity: .resizeAspectFill
            )
        )

        XCTAssertTrue(session.layerSnapshot === firstLayer)
        XCTAssertTrue(session.attachedPlayer === secondPlayer)
        XCTAssertEqual(session.layerSnapshot?.frame.size.width, 200)
        XCTAssertEqual(
            session.layerSnapshot?.videoGravity,
            .resizeAspectFill
        )
        XCTAssertEqual(session.diagnostics.layerGeneration, 1)
        XCTAssertEqual(session.diagnostics.attachmentCount, 2)
    }

    func testLayoutAndGravityOperateOnOwnedLayer() {
        let session = IRGLAVPlayerLayerSession()
        XCTAssertTrue(
            session.setPlayer(
                AVPlayer(),
                hostLayer: CALayer(),
                bounds: .zero,
                gravity: .resizeAspect
            )
        )

        session.layout(
            bounds: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        session.updateGravity(.resize)

        XCTAssertEqual(session.layerSnapshot?.frame.size.width, 320)
        XCTAssertEqual(session.layerSnapshot?.frame.size.height, 180)
        XCTAssertEqual(session.layerSnapshot?.videoGravity, .resize)
        XCTAssertEqual(session.diagnostics.layoutCount, 1)
    }

    func testNilPlayerDetachesAndNextAttachCreatesNewGeneration() {
        let session = IRGLAVPlayerLayerSession()
        let hostLayer = CALayer()
        XCTAssertTrue(
            session.setPlayer(
                AVPlayer(),
                hostLayer: hostLayer,
                bounds: .zero,
                gravity: .resizeAspect
            )
        )

        XCTAssertTrue(
            session.setPlayer(
                nil,
                hostLayer: hostLayer,
                bounds: .zero,
                gravity: .resizeAspect
            )
        )
        XCTAssertNil(session.layerSnapshot)
        XCTAssertEqual(session.diagnostics.detachCount, 1)

        XCTAssertTrue(
            session.setPlayer(
                AVPlayer(),
                hostLayer: hostLayer,
                bounds: .zero,
                gravity: .resizeAspect
            )
        )
        XCTAssertEqual(session.diagnostics.layerGeneration, 2)
    }

    func testCloseIsTerminalAndIdempotent() {
        let session = IRGLAVPlayerLayerSession()
        XCTAssertTrue(
            session.setPlayer(
                AVPlayer(),
                hostLayer: CALayer(),
                bounds: .zero,
                gravity: .resizeAspect
            )
        )

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(
            session.setPlayer(
                AVPlayer(),
                hostLayer: CALayer(),
                bounds: .zero,
                gravity: .resizeAspect
            )
        )
        XCTAssertTrue(session.diagnostics.isClosed)
        XCTAssertFalse(session.diagnostics.hasLayer)
        XCTAssertFalse(session.diagnostics.hasPlayer)
    }
}

final class IRGLRenderSessionTests: XCTestCase {
    private var unavailableSurface:
        IRGLMetalSurfaceDependencies
    {
        IRGLMetalSurfaceDependencies(
            makeDevice: { nil },
            makeCommandQueue: { _ in nil },
            makeCIContext: { _ in nil },
            makeRenderer: {
                _,
                _ in .failure(.missingShaderLibrary)
            }
        )
    }

    private func makeInput(
        layer: CAMetalLayer = CAMetalLayer(),
        bounds: CGRect = CGRect(x: 0, y: 0, width: 100, height: 50)
    ) -> IRGLMetalSurfaceSession.Input {
        .init(
            layer: layer,
            bounds: bounds,
            screenScale: 2
        )
    }

    func testPrepareOwnsModesEvenWhenMetalIsUnavailable() {
        let modes = [IRGLRenderMode2D(), IRGLRenderModeVR()]
        let session = IRGLRenderSession(
            surfaceDependencies: unavailableSurface,
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )

        XCTAssertFalse(
            session.prepare(
                surfaceInput: makeInput(),
                pixelFormat: .YUV_IRPixelFormat,
                replacingModes: modes
            )
        )

        XCTAssertEqual(session.registeredModes.count, 2)
        XCTAssertTrue(session.selectedMode === modes[0])
        XCTAssertNotNil(modes[0].program)
        XCTAssertNil(modes[0].renderer)
        XCTAssertEqual(
            session.diagnostics.surface.phase,
            .unavailable(.missingDevice)
        )
    }

    func testSelectionRequiresRegisteredIdentity() {
        let first = IRGLRenderMode2D()
        let second = IRGLRenderModeVR()
        let session = IRGLRenderSession(
            surfaceDependencies: unavailableSurface
        )
        _ = session.prepare(
            surfaceInput: makeInput(),
            pixelFormat: .YUV_IRPixelFormat,
            replacingModes: [first, second]
        )

        let selected = session.select(
            second,
            renderImmediately: false
        )
        let rejected = session.select(
            IRGLRenderModeVR(),
            renderImmediately: false
        )

        XCTAssertTrue(selected.didSelect)
        XCTAssertTrue(session.selectedMode === second)
        XCTAssertFalse(rejected.didSelect)
        XCTAssertEqual(session.diagnostics.modeSelectionCount, 1)
        XCTAssertEqual(session.diagnostics.rejectedOperationCount, 1)
    }

    func testPixelFormatChangeRebuildsProgram() {
        let mode = IRGLRenderMode2D()
        let session = IRGLRenderSession(
            surfaceDependencies: unavailableSurface
        )
        _ = session.prepare(
            surfaceInput: makeInput(),
            pixelFormat: .YUV_IRPixelFormat,
            replacingModes: [mode]
        )
        let firstProgram = mode.program

        _ = session.prepare(
            surfaceInput: makeInput(),
            pixelFormat: .RGB_IRPixelFormat
        )

        XCTAssertNotNil(firstProgram)
        XCTAssertNotNil(mode.program)
        XCTAssertFalse(mode.program === firstProgram)
        XCTAssertEqual(
            session.currentPixelFormat,
            .RGB_IRPixelFormat
        )
    }

    func testPrepareSubmitResizeAndCloseLifecycle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let completed = IRGLOwnerCounter()
        let layer = CAMetalLayer()
        let session = IRGLRenderSession(
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        session.setRenderCompletionHandler(completed.increment)

        XCTAssertTrue(
            session.prepare(
                surfaceInput: makeInput(layer: layer),
                pixelFormat: .YUV_IRPixelFormat
            )
        )
        XCTAssertEqual(session.currentViewportRange.width, 200)
        XCTAssertEqual(session.currentViewportRange.height, 100)

        let frame = IRFFVideoFrame()
        frame.width = 640
        frame.height = 360
        XCTAssertTrue(session.submit(frame))
        XCTAssertTrue(
            session.resize(
                surfaceInput: makeInput(
                    layer: layer,
                    bounds: CGRect(
                        x: 0,
                        y: 0,
                        width: 80,
                        height: 40
                    )
                )
            )
        )

        XCTAssertEqual(session.lastFrameSize.width, 640)
        XCTAssertEqual(session.lastFrameSize.height, 360)
        XCTAssertEqual(session.currentViewportRange.width, 160)
        XCTAssertEqual(session.currentViewportRange.height, 80)
        XCTAssertEqual(completed.value, 2)
        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(session.submit(frame))
        XCTAssertTrue(session.diagnostics.isClosed)
        XCTAssertEqual(session.diagnostics.surface.phase, .closed)
        XCTAssertTrue(session.diagnostics.frames.isClosed)
    }

    func testResetReleasesSurfaceAndModeRendererGeneration() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal device unavailable")
        }
        let mode = IRGLRenderMode2D()
        let layer = CAMetalLayer()
        let session = IRGLRenderSession()
        XCTAssertTrue(
            session.prepare(
                surfaceInput: makeInput(layer: layer),
                pixelFormat: .YUV_IRPixelFormat,
                replacingModes: [mode]
            )
        )
        XCTAssertNotNil(mode.renderer)

        session.reset()

        XCTAssertNil(mode.renderer)
        XCTAssertEqual(session.diagnostics.surface.phase, .idle)
        XCTAssertFalse(
            session.diagnostics.surface.hasCompleteResources
        )
        XCTAssertNil(layer.device)
        XCTAssertEqual(session.currentViewportRange, .zero)
    }

    func testConcurrentSubmissionsUseSingleExecutionDomain() {
        let session = IRGLRenderSession(
            surfaceDependencies: unavailableSurface,
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        _ = session.prepare(
            surfaceInput: makeInput(),
            pixelFormat: .YUV_IRPixelFormat
        )

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertTrue(session.submit(IRFFVideoFrame()))
        }

        XCTAssertEqual(session.diagnostics.frames.submissionCount, 100)
        XCTAssertEqual(
            session.diagnostics.frames.completedRenderCount,
            100
        )
    }

    func testNestedOperationsAreReentrantSafe() {
        let session = IRGLRenderSession(
            surfaceDependencies: unavailableSurface,
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        _ = session.prepare(
            surfaceInput: makeInput(),
            pixelFormat: .YUV_IRPixelFormat
        )

        session.runSync {
            XCTAssertTrue(session.isCurrentExecutor)
            XCTAssertTrue(session.submit(IRFFVideoFrame()))
            _ = session.diagnostics
        }

        XCTAssertGreaterThan(
            session.diagnostics.executor.reentrantEntryCount,
            0
        )
    }
}

final class IRGLViewRuntimeOwnerTests: XCTestCase {
    func testCloseFromRenderExecutorIsDeadlockSafeAndTerminal() {
        let renderSession = IRGLRenderSession(
            surfaceDependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { nil },
                makeCommandQueue: { _ in nil },
                makeCIContext: { _ in nil },
                makeRenderer: {
                    _,
                    _ in .failure(.missingShaderLibrary)
                }
            ),
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        let snapshotSession = IRGLSnapshotSession(
            dependencies: IRGLSnapshotDependencies(
                dispatchToMain: { $0() },
                saveImage: { _ in }
            )
        )
        let layerSession = IRGLAVPlayerLayerSession()
        let view = IRMainThreadExecutor.sync {
            IRGLView(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                runtimeDependencies: IRGLViewRuntimeDependencies(
                    renderSession: renderSession,
                    snapshotSession: snapshotSession,
                    avPlayerLayerSession: layerSession
                )
            )
        }

        view.runSyncInQueue {
            view.close()
        }

        XCTAssertTrue(renderSession.diagnostics.isClosed)
        XCTAssertTrue(snapshotSession.diagnostics.isClosed)
    }

    func testSnapshotRequestFlowsOnlyAfterCompletedRender() {
        let dispatcher = IRGLDeferredDispatcher()
        let saves = IRGLOwnerCounter()
        let renderSession = IRGLRenderSession(
            surfaceDependencies: IRGLMetalSurfaceDependencies(
                makeDevice: { nil },
                makeCommandQueue: { _ in nil },
                makeCIContext: { _ in nil },
                makeRenderer: {
                    _,
                    _ in .failure(.missingShaderLibrary)
                }
            ),
            frameRenderOperation: { input in
                .init(
                    currentImage: input.currentImage,
                    didCompleteRender: true
                )
            }
        )
        let snapshotSession = IRGLSnapshotSession(
            dependencies: IRGLSnapshotDependencies(
                dispatchToMain: dispatcher.dispatch,
                saveImage: { _ in saves.increment() }
            )
        )
        let view = IRMainThreadExecutor.sync {
            IRGLView(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                runtimeDependencies: IRGLViewRuntimeDependencies(
                    renderSession: renderSession,
                    snapshotSession: snapshotSession,
                    avPlayerLayerSession:
                        IRGLAVPlayerLayerSession()
                )
            )
        }

        view.doSnapShot()
        XCTAssertEqual(dispatcher.count, 0)
        view.render(IRFFVideoFrame())

        XCTAssertEqual(dispatcher.count, 1)
        XCTAssertEqual(saves.value, 0)
        dispatcher.runAll()
        XCTAssertEqual(saves.value, 1)
        XCTAssertEqual(
            snapshotSession.diagnostics.savedCaptureCount,
            1
        )
        view.close()
    }
}
