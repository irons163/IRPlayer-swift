import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFAudioRendererTests: XCTestCase {
    func testInactiveRendererAlwaysWritesSilence() {
        let renderer = IRFFAudioRenderer()
        var output = [Float](repeating: 7, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testRendererFetchesAndConsumesFramesAcrossCallbacks() {
        let frame = makeRendererAudioFrame([1, 2, 3, 4])
        let source = TestAudioFrameSource(frames: [frame])
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var first = [Float](repeating: 0, count: 2)
        var second = [Float](repeating: 0, count: 2)

        first.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(first, [1, 2])
        XCTAssertTrue(renderer.currentFrame === frame)
        // The render cursor belongs exclusively to the callback-owned lease.
        // Keeping the frame metadata unchanged avoids a callback/control-path
        // data race while the next callback still resumes at the right sample.
        XCTAssertEqual(frame.outputOffset, 0)

        second.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(second, [3, 4])
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(frame.playing)
        XCTAssertEqual(source.fetchCount, 1)
    }

    func testRendererConsumesMultipleFramesWithoutChangingStorageCapacity() {
        let firstFrame = makeRendererAudioFrame([1, 2])
        let secondFrame = makeRendererAudioFrame([3, 4])
        let firstCapacity = firstFrame.sampleCapacity
        let secondCapacity = secondFrame.sampleCapacity
        let source = TestAudioFrameSource(
            frames: [firstFrame, secondFrame]
        )
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var output = [Float](repeating: 0, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [1, 2, 3, 4])
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(firstFrame.playing)
        XCTAssertFalse(secondFrame.playing)
        XCTAssertEqual(source.fetchCount, 2)
        XCTAssertEqual(firstFrame.sampleCapacity, firstCapacity)
        XCTAssertEqual(secondFrame.sampleCapacity, secondCapacity)
    }

    func testFrameCompletionRetriesBeforeFetchingAnotherFrame() {
        let firstFrame = makeRendererAudioFrame([1, 2])
        let secondFrame = makeRendererAudioFrame([3, 4])
        let source = TestAudioFrameSource(
            frames: [firstFrame, secondFrame]
        )
        source.setFinishResults([false, true, true])
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var firstOutput = [Float](repeating: 0, count: 2)
        var secondOutput = [Float](repeating: 0, count: 2)

        firstOutput.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(firstOutput, [1, 2])
        XCTAssertEqual(source.fetchCount, 1)
        XCTAssertEqual(source.finishCount, 1)

        secondOutput.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(secondOutput, [3, 4])
        XCTAssertEqual(source.fetchCount, 2)
        XCTAssertEqual(source.finishCount, 3)
    }

    func testControlResetSynchronouslyAcknowledgesPendingFrame() {
        let frame = makeRendererAudioFrame([1, 2])
        let source = TestAudioFrameSource(frames: [frame])
        source.setFinishResults([false])
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var output = [Float](repeating: 0, count: 2)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(output, [1, 2])
        XCTAssertEqual(source.finishCount, 1)
        XCTAssertEqual(source.synchronousFinishCount, 0)

        renderer.reset()

        XCTAssertEqual(source.synchronousFinishCount, 1)
        XCTAssertFalse(renderer.diagnostics.hasSource)
        XCTAssertNil(renderer.currentFrame)
    }

    func testRenderCallbackNeverInvokesFrameLifecycleDelegate() {
        let frame = makeRendererAudioFrame([1, 2])
        let lifecycle = AudioFrameLifecycleProbe()
        frame.delegate = lifecycle
        let source = TestAudioFrameSource(frames: [frame])
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var output = [Float](repeating: 0, count: 2)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [1, 2])
        XCTAssertEqual(lifecycle.callbackCount, 0)
        XCTAssertEqual(source.finishCount, 1)
    }

    func testMissingSamplesOrInvalidOffsetStopsCurrentFrame() {
        let missingSamples = IRFFAudioFrame()
        let renderer = IRFFAudioRenderer()
        renderer.replaceCurrentFrame(missingSamples)
        renderer.setEnabled(true)
        var output = [Float](repeating: 5, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(output, [0, 0, 0, 0])
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(missingSamples.playing)

        let invalidOffset = makeRendererAudioFrame([1, 2, 3, 4])
        invalidOffset.outputOffset = 1
        renderer.replaceCurrentFrame(invalidOffset)
        output = [Float](repeating: 5, count: 4)
        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(output, [0, 0, 0, 0])
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(invalidOffset.playing)
    }

    func testSourceIsRetainedThroughFrameAcknowledgmentThenReleased() {
        let renderer = IRFFAudioRenderer()
        let frame = makeRendererAudioFrame([1, 2])
        weak var weakSource: TestAudioFrameSource?

        autoreleasepool {
            let source = TestAudioFrameSource(frames: [frame])
            weakSource = source
            renderer.attachSource(source)
            renderer.replaceCurrentFrame(frame)
        }
        XCTAssertNotNil(weakSource)
        renderer.attachSource(nil)

        XCTAssertNil(weakSource)
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(frame.playing)
        XCTAssertFalse(renderer.diagnostics.hasSource)
    }

    func testContendedCallbackReturnsSilenceWithoutWaiting() {
        let frame = makeRendererAudioFrame([1, 2, 3, 4])
        let source = TestAudioFrameSource(frames: [frame])
        let fetchEntered = DispatchSemaphore(value: 0)
        let resumeFetch = DispatchSemaphore(value: 0)
        source.onFetch = {
            fetchEntered.signal()
            _ = resumeFetch.wait(timeout: .now() + 2)
        }
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)

        let firstFinished = expectation(description: "first render")
        DispatchQueue.global().async {
            var output = [Float](repeating: 0, count: 4)
            output.withUnsafeMutableBufferPointer { buffer in
                renderer.audioManager(
                    makeTestAudioManager(),
                    outputData: buffer.baseAddress!,
                    numberOfFrames: 2,
                    numberOfChannels: 2
                )
            }
            firstFinished.fulfill()
        }
        XCTAssertEqual(fetchEntered.wait(timeout: .now() + 1), .success)

        var second = [Float](repeating: 9, count: 4)
        second.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }
        XCTAssertEqual(second, [0, 0, 0, 0])

        resumeFetch.signal()
        wait(for: [firstFinished], timeout: 2)
    }

    func testResetWaitsForRenderThenStopsAndDrainsFrame() {
        let frame = makeRendererAudioFrame([1, 2, 3, 4])
        let source = TestAudioFrameSource(frames: [frame])
        let fetchEntered = DispatchSemaphore(value: 0)
        let resumeFetch = DispatchSemaphore(value: 0)
        source.onFetch = {
            fetchEntered.signal()
            _ = resumeFetch.wait(timeout: .now() + 2)
        }
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)

        let renderFinished = expectation(description: "render")
        DispatchQueue.global().async {
            var output = [Float](repeating: 0, count: 2)
            output.withUnsafeMutableBufferPointer { buffer in
                renderer.audioManager(
                    makeTestAudioManager(),
                    outputData: buffer.baseAddress!,
                    numberOfFrames: 1,
                    numberOfChannels: 2
                )
            }
            renderFinished.fulfill()
        }
        XCTAssertEqual(fetchEntered.wait(timeout: .now() + 1), .success)

        let resetFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            renderer.reset()
            resetFinished.signal()
        }
        XCTAssertEqual(
            resetFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )

        resumeFetch.signal()
        wait(for: [renderFinished], timeout: 2)
        XCTAssertEqual(
            resetFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertFalse(renderer.diagnostics.enabled)
        XCTAssertFalse(renderer.diagnostics.hasSource)
        XCTAssertNil(renderer.currentFrame)
        XCTAssertFalse(frame.playing)
    }

    func testRenderUsesQueueAdmissionByteCountInsteadOfLiveMetadata() {
        let frame = makeRendererAudioFrame([1, 2, 3, 4])
        let source = TestAudioFrameSource(frames: [frame])
        // Once admitted, transport metadata is no longer authoritative for
        // the callback. A decoder/pool bug must not make the callback wait on
        // or trust this live value.
        frame.size = Int.max
        let renderer = IRFFAudioRenderer()
        renderer.attachSource(source)
        renderer.setEnabled(true)
        var output = [Float](repeating: 0, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            renderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [1, 2, 3, 4])
        XCTAssertNil(renderer.currentFrame)
        XCTAssertEqual(source.finishCount, 1)
    }

    func testCopyPlanRejectsOverflowAndCopiesOnlyWholeFrames() throws {
        XCTAssertNil(
            IRFFAudioRenderer.copyPlan(
                frameSize: Int.max,
                outputOffset: 0,
                remainingFrames: .max,
                numberOfChannels: .max
            )
        )
        XCTAssertNil(
            IRFFAudioRenderer.copyPlan(
                frameSize: 128,
                outputOffset: 1,
                remainingFrames: 2,
                numberOfChannels: 2
            )
        )

        let plan = try XCTUnwrap(
            IRFFAudioRenderer.copyPlan(
                frameSize: 10,
                outputOffset: 0,
                remainingFrames: 2,
                numberOfChannels: 2
            )
        )
        XCTAssertEqual(plan.bytesToCopy, 8)
        XCTAssertEqual(plan.framesToCopy, 1)
        XCTAssertTrue(plan.hasRemainingFrameBytes)
    }
}

private final class TestAudioFrameSource:
    IRFFAudioFrameSource,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var frames: [IRFFAudioRenderLease]
    private var storedFetchCount = 0
    private var storedFinishCount = 0
    private var storedSynchronousFinishCount = 0
    private var finishResults: [Bool] = []
    var onFetch: (() -> Void)?

    init(frames: [IRFFAudioFrame]) {
        self.frames = frames.map {
            IRFFAudioRenderLease(
                frame: $0,
                byteCount: $0.size,
                outputOffset: $0.outputOffset
            )
        }
    }

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFetchCount
    }

    var finishCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFinishCount
    }

    var synchronousFinishCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedSynchronousFinishCount
    }

    func setFinishResults(_ results: [Bool]) {
        lock.lock()
        finishResults = results
        lock.unlock()
    }

    func fetchAudioFrame() -> IRFFAudioRenderLease? {
        lock.lock()
        storedFetchCount += 1
        let onFetch = onFetch
        let lease = frames.isEmpty ? nil : frames.removeFirst()
        lock.unlock()
        onFetch?()
        return lease
    }

    func finishAudioFrame(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        lock.lock()
        storedFinishCount += 1
        let result = finishResults.isEmpty
            ? true
            : finishResults.removeFirst()
        lock.unlock()
        return result
    }

    func finishAudioFrameSynchronously(
        _ identifier: ObjectIdentifier
    ) -> Bool {
        lock.lock()
        storedSynchronousFinishCount += 1
        lock.unlock()
        return true
    }
}

private final class AudioFrameLifecycleProbe:
    NSObject,
    IRFFFrameDelegate
{
    private let lock = NSLock()
    private var storedCallbackCount = 0

    var callbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallbackCount
    }

    func frameDidStartPlaying(_ frame: IRFFFrame) {
        record()
    }

    func frameDidStopPlaying(_ frame: IRFFFrame) {
        record()
    }

    func frameDidCancel(_ frame: IRFFFrame) {
        record()
    }

    private func record() {
        lock.lock()
        storedCallbackCount += 1
        lock.unlock()
    }
}

private func makeRendererAudioFrame(_ values: [Float]) -> IRFFAudioFrame {
    let frame = IRFFAudioFrame()
    frame.setSamplesLength(values.count * MemoryLayout<Float>.stride)
    frame.withMutableSamples { samples in
        for (index, value) in values.enumerated() {
            samples[index] = value
        }
        return true
    }
    return frame
}
