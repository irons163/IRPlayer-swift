import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFVideoDecoderTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30),
            IRFFVideoDecoderPolicy.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(frameDuration: 2.0, maxDecodeDuration: 2.0, paused: true),
            IRFFVideoDecoderPolicy.decodeBackpressureSleepInterval(frameDuration: 2.0, maxDecodeDuration: 2.0, paused: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetDecodeResultIsFailure(-1),
            IRFFVideoDecoderPolicy.packetDecodeResultIsFailure(-1)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: true),
            IRFFVideoDecoderPolicy.shouldFinishDecode(endOfFile: true, packetEmpty: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeIdleSleepInterval(paused: true),
            IRFFVideoDecoderPolicy.decodeIdleSleepInterval(paused: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.shouldCreateYUVFrame(hasFrame: true, hasLuma: true, hasChromaB: true, hasChromaR: true),
            IRFFVideoDecoderPolicy.shouldCreateYUVFrame(hasFrame: true, hasLuma: true, hasChromaB: true, hasChromaR: true)
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 0,
                                                         packetSize: 1,
                                                         isFlushPacket: false,
                                                         timebase: 0.25,
                                                         fps: 30),
            IRFFVideoDecoderPolicy.packetQueueFallbackDuration(packetDuration: 0,
                                                               packetSize: 1,
                                                               isFlushPacket: false,
                                                               timebase: 0.25,
                                                               fps: 30)
        )
    }

    func testFlushPacketWrapperMatchesSentinelBuilder() {
        let packet = IRFFVideoDecoder.makeFlushPacket()

        XCTAssertNotNil(packet.data)
        XCTAssertEqual(packet.duration, 0)
        XCTAssertNotNil(IRFFVideoDecoder.flushPacket.data)
        XCTAssertEqual(IRFFVideoDecoder.flushPacket.duration, 0)
    }

    func testFrameDurationUsesTicksAndRepeatPictureWhenAvailable() {
        let duration = IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 2, timebase: 0.25, fps: 30)

        XCTAssertEqual(duration, 1.25, accuracy: 0.0001)
    }

    func testFrameDurationIgnoresNegativeRepeatPicture() {
        let duration = IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: -8, timebase: 0.25, fps: 30)

        XCTAssertEqual(duration, 1, accuracy: 0.0001)
    }

    func testFrameDurationUsesFPSFallbackWhenTicksAreMissing() {
        let duration = IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: 25)

        XCTAssertEqual(duration, 0.04, accuracy: 0.0001)
    }

    func testFrameDurationRejectsInvalidTimingInputs() {
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 0, timebase: .infinity, fps: 30), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 4, repeatPicture: 0, timebase: -1, fps: 30), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: 0), 0)
        XCTAssertEqual(IRFFVideoDecoder.frameDuration(ticks: 0, repeatPicture: 0, timebase: 0.25, fps: .nan), 0)
    }

    func testDecodeBackpressureSleepIntervalUsesConfiguredThresholdAndPauseState() {
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 1.99,
                maxDecodeDuration: 2.0,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: 2.0,
                paused: false
            ),
            0.1
        )
        XCTAssertEqual(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 3.0,
                maxDecodeDuration: 2.0,
                paused: true
            ),
            0.5
        )
    }

    func testDecodeBackpressureSleepIntervalRejectsInvalidTimingInputs() {
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: .nan,
                maxDecodeDuration: 2.0,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: 0,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: -1,
                paused: false
            )
        )
        XCTAssertNil(
            IRFFVideoDecoder.decodeBackpressureSleepInterval(
                frameDuration: 2.0,
                maxDecodeDuration: .infinity,
                paused: false
            )
        )
    }

    func testPacketDecodeResultPolicyTreatsRecoverableFFmpegResultsAsNonFailures() {
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(0))
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(AVERROR(EAGAIN)))
        XCTAssertTrue(IRFFVideoDecoder.packetDecodeResultIsFailure(-1))
    }

    func testShouldFinishDecodeRequiresEndOfFileAndEmptyPacketQueue() {
        XCTAssertFalse(IRFFVideoDecoder.shouldFinishDecode(endOfFile: false, packetEmpty: true))
        XCTAssertFalse(IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: false))
        XCTAssertTrue(IRFFVideoDecoder.shouldFinishDecode(endOfFile: true, packetEmpty: true))
    }

    func testDecodeIdleSleepIntervalOnlyAppliesWhenPaused() {
        XCTAssertEqual(IRFFVideoDecoder.decodeIdleSleepInterval(paused: true), 0.01)
        XCTAssertNil(IRFFVideoDecoder.decodeIdleSleepInterval(paused: false))
    }

    func testShouldCreateYUVFrameRequiresFrameAndAllPlanes() {
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: false,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: false,
                hasChromaB: true,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: false,
                hasChromaR: true
            )
        )
        XCTAssertFalse(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: false
            )
        )
        XCTAssertTrue(
            IRFFVideoDecoder.shouldCreateYUVFrame(
                hasFrame: true,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true
            )
        )
    }

    func testPacketQueueFallbackDurationAppliesOnlyToPayloadPacketsWithoutDuration() {
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 0,
                                                         packetSize: 32,
                                                         isFlushPacket: false,
                                                         timebase: 0.25,
                                                         fps: 25),
            0.04,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 4,
                                                         packetSize: 32,
                                                         isFlushPacket: false,
                                                         timebase: 0.25,
                                                         fps: 25),
            0
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 0,
                                                         packetSize: 0,
                                                         isFlushPacket: false,
                                                         timebase: 0.25,
                                                         fps: 25),
            0
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 0,
                                                         packetSize: 32,
                                                         isFlushPacket: true,
                                                         timebase: 0.25,
                                                         fps: 25),
            0
        )
    }

    func testQueueStateFlushDestroyAndFrameOutputRemainCallable() {
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            let frame = IRFFVideoFrame()
            frame.duration = 0.5
            frame.size = 12

            XCTAssertEqual(decoder.packetSize(), 0)
            XCTAssertTrue(decoder.empty())
            XCTAssertTrue(decoder.packetEmpty())
            XCTAssertTrue(decoder.frameEmpty())
            XCTAssertEqual(decoder.duration(), 0)
            XCTAssertEqual(decoder.packetDuration(), 0)
            XCTAssertEqual(decoder.frameDuration(), 0)
            XCTAssertNil(decoder.getFrameAsync())

            decoder.send(videoFrame: frame)

            XCTAssertFalse(decoder.empty())
            XCTAssertFalse(decoder.frameEmpty())
            XCTAssertEqual(decoder.frameDuration(), 0.5)
            XCTAssertTrue(decoder.getFrameAsync() === frame)
            XCTAssertTrue(decoder.frameEmpty())

            var packet = AVPacket()
            packet.duration = 4
            packet.size = 32

            decoder.putPacket(packet)

            XCTAssertFalse(decoder.packetEmpty())
            XCTAssertEqual(decoder.packetSize(), 32)
            XCTAssertEqual(decoder.packetDuration(), 1, accuracy: 0.0001)

            decoder.flush()

            XCTAssertFalse(decoder.packetEmpty())
            XCTAssertEqual(decoder.packetSize(), 0)
            XCTAssertEqual(decoder.packetDuration(), 0)

            decoder.destroy()

            XCTAssertTrue(decoder.packetEmpty())
            XCTAssertTrue(decoder.frameEmpty())
            XCTAssertNil(decoder.getFrameAsync())
            XCTAssertNil(decoder.getFrameSync())
        }
    }

    func testDecodeFrameThreadFinishesAtEndOfFileWithoutPackets() {
        var codecContext = AVCodecContext()
        let delegate = VideoDecoderDelegateSpy()

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )

            decoder.endOfFile = true
            decoder.decodeFrameThread()

            XCTAssertFalse(decoder.decoding)
        }

        XCTAssertEqual(delegate.bufferingCheckCallCount, 1)
        XCTAssertEqual(delegate.bufferedDurationUpdateCallCount, 0)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testDecodeFrameThreadUsesSourceFrameBeforeFinishingAtEndOfFile() {
        var codecContext = AVCodecContext()
        let delegate = VideoDecoderDelegateSpy()
        let sourceFrame = IRFFVideoFrame()
        sourceFrame.duration = 0.5
        sourceFrame.size = 12
        let source = VideoDecoderDataSourceSpy(shouldHandle: true, frame: sourceFrame)

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            decoder.source = source
            decoder.endOfFile = true

            var packet = AVPacket()
            packet.stream_index = 0
            packet.duration = 1
            packet.size = 1
            var byte: UInt8 = 1
            withUnsafeMutablePointer(to: &byte) { pointer in
                packet.data = pointer
                decoder.putPacket(packet)
                decoder.decodeFrameThread()
            }

            XCTAssertFalse(decoder.decoding)
            XCTAssertTrue(decoder.getFrameAsync() === sourceFrame)
            XCTAssertTrue(decoder.frameEmpty())
        }

        XCTAssertEqual(source.shouldHandleCallCount, 1)
        XCTAssertEqual(source.decodeFrameCallCount, 1)
        XCTAssertEqual(delegate.bufferedDurationUpdateCallCount, 1)
        XCTAssertEqual(delegate.bufferingCheckCallCount, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testRuntimeConfigurationSupportsConcurrentReadsAndWrites() {
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            let workers = DispatchGroup()
            let workQueue = DispatchQueue(
                label: "IRFFVideoDecoderTests.runtime",
                attributes: .concurrent
            )

            for worker in 0..<4 {
                workers.enter()
                workQueue.async {
                    for iteration in 0..<1_000 {
                        decoder.paused = (iteration + worker).isMultiple(of: 2)
                        decoder.endOfFile = (iteration + worker).isMultiple(of: 3)
                        decoder.videoToolBoxEnable = (iteration + worker).isMultiple(of: 5)
                        decoder.maxDecodeDuration = TimeInterval(iteration + 1) / 1_000
                        _ = decoder.paused
                        _ = decoder.endOfFile
                        _ = decoder.videoToolBoxEnable
                        _ = decoder.maxDecodeDuration
                        _ = decoder.decoding
                        _ = decoder.error
                    }
                    workers.leave()
                }
            }

            XCTAssertEqual(workers.wait(timeout: .now() + 5), .success)
            decoder.paused = false
            decoder.endOfFile = true
            decoder.videoToolBoxEnable = false
            decoder.maxDecodeDuration = 1

            XCTAssertFalse(decoder.paused)
            XCTAssertTrue(decoder.endOfFile)
            XCTAssertFalse(decoder.videoToolBoxEnable)
            XCTAssertEqual(decoder.maxDecodeDuration, 1)
        }
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var codecContext = AVCodecContext()

        let output = withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            var decoder: IRFFVideoDecoder? = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            XCTAssertNotNil(decoder)

            return captureStandardOutput {
                decoder = nil
            }
        }

        XCTAssertEqual(output, "")
    }
}

private final class VideoDecoderDelegateSpy: IRFFVideoDecoderDelegate {
    private(set) var errors: [NSError] = []
    private(set) var bufferedDurationUpdateCallCount = 0
    private(set) var bufferingCheckCallCount = 0

    func videoDecoder(_ videoDecoder: IRFFVideoDecoder, didError error: Error) {
        errors.append(error as NSError)
    }

    func videoDecoderNeedUpdateBufferedDuration(_ videoDecoder: IRFFVideoDecoder) {
        bufferedDurationUpdateCallCount += 1
    }

    func videoDecoderNeedCheckBufferingStatus(_ videoDecoder: IRFFVideoDecoder) {
        bufferingCheckCallCount += 1
    }
}

private final class VideoDecoderDataSourceSpy: IRFFVideoDecoderDataSource {
    private let shouldHandleResult: Bool
    private let frame: IRFFVideoFrame?
    private(set) var shouldHandleCallCount = 0
    private(set) var decodeFrameCallCount = 0

    init(shouldHandle: Bool, frame: IRFFVideoFrame?) {
        self.shouldHandleResult = shouldHandle
        self.frame = frame
    }

    func shouldHandle(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> Bool {
        shouldHandleCallCount += 1
        return shouldHandleResult
    }

    func videoDecoder(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> IRFFVideoFrame? {
        decodeFrameCallCount += 1
        return frame
    }
}
