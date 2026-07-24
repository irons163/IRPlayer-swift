import XCTest
@testable import IRPlayer_swift

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
        XCTAssertEqual(frame.outputOffset, 2 * MemoryLayout<Float>.stride)

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

    func testMissingSamplesOrInvalidOffsetStopsCurrentFrame() {
        let missingSamples = IRFFAudioFrame()
        missingSamples.startPlaying()
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

    func testReplacingSourceStopsFrameAndDoesNotRetainSources() {
        let renderer = IRFFAudioRenderer()
        let frame = makeRendererAudioFrame([1, 2])
        weak var weakSource: TestAudioFrameSource?

        autoreleasepool {
            let source = TestAudioFrameSource(frames: [frame])
            weakSource = source
            renderer.attachSource(source)
            renderer.replaceCurrentFrame(frame)
        }
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
    private var frames: [IRFFAudioFrame]
    private var storedFetchCount = 0
    var onFetch: (() -> Void)?

    init(frames: [IRFFAudioFrame]) {
        self.frames = frames
    }

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFetchCount
    }

    func fetchAudioFrame() -> IRFFAudioFrame? {
        lock.lock()
        storedFetchCount += 1
        let onFetch = onFetch
        let frame = frames.isEmpty ? nil : frames.removeFirst()
        lock.unlock()
        onFetch?()
        return frame
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
    frame.startPlaying()
    return frame
}
