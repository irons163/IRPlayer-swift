import CoreGraphics
import Foundation
import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFDecoder.audioPacketError(fromPacketResult: -1)?.code,
            IRFFDecoderAudioPolicy.audioPacketError(fromPacketResult: -1)?.code
        )
        XCTAssertEqual(
            IRFFDecoder.bufferedDurationTransition(bufferedDuration: 0, endOfFile: true),
            IRFFDecoderAudioPolicy.bufferedDurationTransition(bufferedDuration: 0, endOfFile: true)
        )
        XCTAssertEqual(
            IRFFDecoder.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            ),
            IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
                audioSize: 4,
                videoPacketSize: 6,
                maxBufferSize: 10,
                paused: false
            )
        )
        XCTAssertEqual(
            IRFFDecoder.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 0,
                duration: 40,
                minBufferedDuration: 2
            ),
            IRFFDecoderSeekPolicy.seekPreparation(
                requestedTime: 30,
                seekEnabled: true,
                hasError: false,
                hasAudio: true,
                seekMinTime: 0,
                duration: 40,
                minBufferedDuration: 2
            )
        )
        XCTAssertEqual(
            IRFFDecoder.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            ),
            IRFFDecoderDisplayPolicy.audioSyncedVideoSleepDuration(
                framePosition: 10,
                frameDuration: 0.04,
                audioTimeClock: 9,
                fps: 25
            )
        )
        XCTAssertEqual(
            IRFFDecoder.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25),
            IRFFDecoderDisplayPolicy.standaloneVideoSleepDuration(frameDuration: 0.04, fps: 25)
        )
        XCTAssertEqual(
            IRFFDecoder.videoFrameOrderingPosition(1.25),
            IRFFDecoderDisplayPolicy.videoFrameOrderingPosition(1.25)
        )
        XCTAssertEqual(
            IRFFDecoder.shouldAcceptVideoFrame(currentPosition: 1, nextPosition: 2),
            IRFFDecoderDisplayPolicy.shouldAcceptVideoFrame(currentPosition: 1, nextPosition: 2)
        )
        XCTAssertEqual(
            IRFFDecoder.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            ),
            IRFFDecoderAudioPolicy.shouldFetchAudioFrame(
                closed: false,
                seeking: false,
                buffering: false,
                paused: false,
                playbackFinished: false,
                audioEnabled: true
            )
        )
        XCTAssertEqual(
            IRFFDecoder.resumeSeekTarget(playbackFinished: true),
            IRFFDecoderSeekPolicy.resumeSeekTarget(playbackFinished: true)
        )
        XCTAssertEqual(
            IRFFDecoder.seekCompletionTransition(seeking: true, progress: 3),
            IRFFDecoderSeekPolicy.seekCompletionTransition(seeking: true, progress: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.readPacketEOFTransition(readFrameResult: -1),
            IRFFDecoderPacketPolicy.readPacketEOFTransition(readFrameResult: -1)
        )
        XCTAssertEqual(
            IRFFDecoder.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3),
            IRFFDecoderPacketPolicy.packetRoute(streamIndex: 2, videoTrackIndex: 2, audioTrackIndex: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: false,
                hasCurrentFrame: false
            ),
            IRFFDecoderDisplayPolicy.displayIdleSleepInterval(
                seeking: true,
                buffering: false,
                paused: false,
                hasCurrentFrame: false
            )
        )
        XCTAssertEqual(
            IRFFDecoder.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true),
            IRFFDecoderDisplayPolicy.shouldFinishDisplay(endOfFile: true, videoDecoderEmpty: true)
        )
        XCTAssertEqual(
            IRFFDecoder.readLoopExitAction(closed: true, hasError: false),
            IRFFDecoderReadLoopState.exitAction(closed: true, hasError: false)
        )
        XCTAssertEqual(
            IRFFDecoder.readLoopSeekCompletionAction(seeking: true, progress: 3),
            IRFFDecoderReadLoopState.seekCompletionAction(seeking: true, progress: 3)
        )
        XCTAssertEqual(
            IRFFDecoder.displayLoopIdleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            ),
            IRFFDecoderDisplayLoopState.idleAction(
                seeking: false,
                buffering: false,
                paused: true,
                hasCurrentFrame: true
            )
        )
        XCTAssertEqual(
            IRFFDecoder.displayLoopFinishAction(endOfFile: true, videoDecoderEmpty: true),
            IRFFDecoderDisplayLoopState.finishAction(endOfFile: true, videoDecoderEmpty: true)
        )
    }

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: formatContext))
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var decoder: IRFFDecoder? = IRFFDecoder(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
        XCTAssertNotNil(decoder)

        let output = captureStandardOutput {
            decoder = nil
        }

        XCTAssertEqual(output, "")
    }

    func testDefaultAccessorsReturnFallbackValuesWithoutPreparedFormatContext() {
        let decoder = makeDecoder()

        XCTAssertEqual(decoder.contentURL.path, "/tmp/decoder-operation-test.mp4")
        XCTAssertEqual(decoder.videoFormat, .mpeg4)
        XCTAssertFalse(decoder.videoEnable)
        XCTAssertFalse(decoder.audioEnable)
        XCTAssertNil(decoder.videoTrack)
        XCTAssertNil(decoder.audioTrack)
        XCTAssertTrue(decoder.videoTracks.isEmpty)
        XCTAssertTrue(decoder.audioTracks.isEmpty)
        XCTAssertTrue(decoder.metadata.isEmpty)
        XCTAssertEqual(decoder.presentationSize, .zero)
        XCTAssertEqual(decoder.aspect, 0)
        XCTAssertEqual(decoder.duration, 0)
        XCTAssertEqual(decoder.bitrate, 0)
        XCTAssertFalse(decoder.seekEnable)
    }

    func testDuplicateOpenSchedulesOneSessionAndReportsOneFailure() {
        let delegate = DecoderDelegateSpy()
        let openFailed = expectation(description: "missing input failed")
        delegate.onError = { openFailed.fulfill() }
        let decoder = makeDecoder()
        decoder.delegate = delegate
        addTeardownBlock {
            decoder.closeFile()
        }

        decoder.open()
        decoder.open()

        wait(for: [openFailed], timeout: 5)
        XCTAssertEqual(delegate.willOpenCount, 1)
        XCTAssertEqual(delegate.preparedCount, 0)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertNotNil(decoder.error)
    }

    func testOpenAfterCloseIsRejectedWithoutPublishingResources() {
        let delegate = DecoderDelegateSpy()
        let decoder = makeDecoder()
        decoder.delegate = delegate

        decoder.closeFile()
        decoder.open()
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertTrue(decoder.closed)
        XCTAssertEqual(delegate.willOpenCount, 0)
        XCTAssertFalse(decoder.prepareToDecode)
        XCTAssertFalse(decoder.videoEnable)
        XCTAssertFalse(decoder.audioEnable)
        XCTAssertNil(decoder.fetchAudioFrame())
    }

    func testOpenGeneratedVideoFilePreparesAndReadsToEndOfFile() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let delegate = DecoderDelegateSpy()
        let prepared = expectation(description: "decoder prepared")
        let endOfFile = expectation(description: "decoder reached EOF")
        delegate.onPrepared = { prepared.fulfill() }
        delegate.onEndOfFile = { endOfFile.fulfill() }

        let decoder = IRFFDecoder(
            contentURL: url,
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
        decoder.delegate = delegate
        decoder.hardwareDecoderEnable = false
        addTeardownBlock {
            decoder.closeFile()
        }

        decoder.open()

        wait(for: [prepared, endOfFile], timeout: 5)

        XCTAssertNil(decoder.error)
        XCTAssertTrue(decoder.prepareToDecode)
        XCTAssertTrue(decoder.videoEnable)
        XCTAssertFalse(decoder.audioEnable)
        XCTAssertEqual(decoder.videoTrack?.type, .video)
        XCTAssertEqual(decoder.videoTracks.map(\.type), [.video])
        XCTAssertTrue(decoder.audioTracks.isEmpty)
        XCTAssertEqual(decoder.presentationSize, CGSize(width: 16, height: 16))
        XCTAssertEqual(decoder.aspect, 1, accuracy: 0.0001)
        XCTAssertTrue(decoder.seekEnable)
        XCTAssertTrue(decoder.endOfFile)
        XCTAssertFalse(decoder.reading)
        XCTAssertEqual(delegate.preparedCount, 1)
        XCTAssertEqual(delegate.endOfFileCount, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testOpenGeneratedVideoFileDisplaysSourceDecodedFrame() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let delegate = DecoderDelegateSpy()
        let output = DecoderVideoOutputSpy()
        let sourceFrame = IRFFVideoFrame()
        sourceFrame.position = 0.03
        sourceFrame.duration = 0.02
        sourceFrame.size = 12
        let source = DecoderVideoDataSourceSpy(shouldHandle: true, frame: sourceFrame)
        let prepared = expectation(description: "decoder prepared")
        let endOfFile = expectation(description: "decoder reached EOF")
        let displayed = expectation(description: "decoder displayed source frame")
        delegate.onPrepared = { prepared.fulfill() }
        delegate.onEndOfFile = { endOfFile.fulfill() }
        output.onFirstFrame = { displayed.fulfill() }

        let decoder = IRFFDecoder(
            contentURL: url,
            videoFormat: .mpeg4,
            videoOutput: output,
            audioOutput: nil
        )
        decoder.delegate = delegate
        decoder.source = source
        decoder.hardwareDecoderEnable = false
        addTeardownBlock {
            decoder.closeFile()
        }

        decoder.open()

        wait(for: [prepared, displayed, endOfFile], timeout: 5)

        XCTAssertNil(decoder.error)
        XCTAssertTrue(decoder.videoEnable)
        XCTAssertFalse(decoder.audioEnable)
        XCTAssertFalse(output.receivedFrames.isEmpty)
        XCTAssertTrue(output.receivedFrames.contains { $0 === sourceFrame })
        XCTAssertGreaterThanOrEqual(source.shouldHandleCallCount, 1)
        XCTAssertGreaterThanOrEqual(source.decodeFrameCallCount, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testOpenGeneratedAudioFileReadsAndFetchesAudioFrame() throws {
        let url = try makeTinyPCM16WAVFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let delegate = DecoderDelegateSpy()
        let audioOutput = DecoderAudioOutputSpy(numberOfChannels: 2, samplingRate: 48_000)
        let prepared = expectation(description: "audio decoder prepared")
        let endOfFile = expectation(description: "audio decoder reached EOF")
        delegate.onPrepared = { prepared.fulfill() }
        delegate.onEndOfFile = { endOfFile.fulfill() }

        let decoder = IRFFDecoder(
            contentURL: url,
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: audioOutput
        )
        decoder.delegate = delegate
        addTeardownBlock {
            decoder.closeFile()
        }

        decoder.open()

        wait(for: [prepared, endOfFile], timeout: 5)

        XCTAssertNil(decoder.error)
        XCTAssertTrue(decoder.audioEnable)
        XCTAssertFalse(decoder.videoEnable)
        XCTAssertEqual(decoder.audioTrack?.type, .audio)
        XCTAssertTrue(delegate.bufferedDurations.contains { $0 > 0 })

        let frame: IRFFAudioFrame = try XCTUnwrap(decoder.fetchAudioFrame())
        XCTAssertGreaterThan(frame.duration, 0)
        XCTAssertEqual(decoder.audioTimeClock, frame.position)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testPauseResumeAndUnseekableSeekUpdateObservableState() {
        let decoder = makeDecoder()
        var seekResult: Bool?

        decoder.pause()
        XCTAssertTrue(decoder.paused)

        decoder.resume()
        XCTAssertFalse(decoder.paused)

        decoder.seek(to: 3) { didFinish in
            seekResult = didFinish
        }

        XCTAssertEqual(seekResult, false)
        XCTAssertFalse(decoder.seeking)
        XCTAssertEqual(decoder.progress, 0)
    }

    func testSeekableDecoderClampsProgressAndNotifiesDelegate() {
        let delegate = DecoderDelegateSpy()
        let decoder = SeekableFFDecoder(duration: 30)
        decoder.delegate = delegate

        decoder.seek(to: 20)

        XCTAssertEqual(decoder.progress, 15)
        XCTAssertTrue(decoder.seeking)
        XCTAssertEqual(delegate.progressValues, [15])
    }

    func testSameValueProgressAndBufferedDurationDoNotNotifyDelegate() {
        let delegate = DecoderDelegateSpy()
        let decoder = makeDecoder()
        decoder.delegate = delegate

        decoder.setValue(0, forKey: "progress")
        decoder.setValue(0, forKey: "bufferedDuration")

        XCTAssertTrue(delegate.progressValues.isEmpty)
        XCTAssertTrue(delegate.bufferedDurations.isEmpty)
    }

    func testResumeAfterPlaybackFinishedSeeksBackToStart() {
        let delegate = DecoderDelegateSpy()
        let decoder = SeekableFFDecoder(duration: 30)
        decoder.delegate = delegate
        decoder.setValue(15, forKey: "progress")
        decoder.setValue(true, forKey: "playbackFinished")

        decoder.resume()

        XCTAssertFalse(decoder.paused)
        XCTAssertTrue(decoder.seeking)
        XCTAssertEqual(decoder.progress, 0)
        XCTAssertEqual(delegate.playbackFinishedCount, 1)
        XCTAssertEqual(delegate.progressValues, [15, 30, 0])
    }

    func testBufferedDurationTransitionNotifiesDelegateAndFinishesAtEndOfFile() {
        let delegate = DecoderDelegateSpy()
        let decoder = SeekableFFDecoder(duration: 9)
        decoder.delegate = delegate

        decoder.setValue(true, forKey: "endOfFile")
        decoder.setValue(0.0000001, forKey: "bufferedDuration")

        XCTAssertEqual(decoder.bufferedDuration, 0)
        XCTAssertTrue(decoder.playbackFinished)
        XCTAssertEqual(decoder.progress, 9)
        XCTAssertEqual(delegate.bufferedDurations, [0])
        XCTAssertEqual(delegate.progressValues, [9])
        XCTAssertEqual(delegate.playbackFinishedCount, 1)
    }

    func testBufferingStateNotifiesDelegateOnlyWhenValueChanges() {
        let delegate = DecoderDelegateSpy()
        let decoder = makeDecoder()
        decoder.delegate = delegate

        decoder.setValue(true, forKey: "buffering")
        decoder.setValue(true, forKey: "buffering")
        decoder.setValue(false, forKey: "buffering")

        XCTAssertEqual(delegate.bufferingValues, [true, false])
    }

    func testFormatContextInterruptReflectsClosedState() {
        let decoder = makeDecoder()
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertFalse(decoder.formatContextNeedInterrupt(formatContext))

        decoder.closeFile()

        XCTAssertTrue(decoder.closed)
        XCTAssertTrue(decoder.formatContextNeedInterrupt(formatContext))
    }

    func testFetchAudioFrameReturnsNilWhenPlaybackStateCannotFetchAudio() {
        let decoder = makeDecoder()

        XCTAssertNil(decoder.fetchAudioFrame())
    }

    func testAudioDecoderDelegateUsesOutputInfoAndDefaultsMissingOutputToZero() {
        var codecContext = AVCodecContext()
        let output = DecoderAudioOutputSpy(numberOfChannels: 6, samplingRate: 44_100)
        let decoder = makeDecoder(audioOutput: output)

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let audioDecoder = IRFFAudioDecoder.decoder(codecContext: codecContextPointer, timebase: 0.001, delegate: decoder)
            var samplingRate: Float64 = -1
            var channelCount: UInt32 = 99

            decoder.audioDecoder(audioDecoder, samplingRate: &samplingRate)
            decoder.audioDecoder(audioDecoder, channelCount: &channelCount)

            XCTAssertEqual(samplingRate, 44_100)
            XCTAssertEqual(channelCount, 6)
        }

        let fallbackDecoder = makeDecoder()
        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let audioDecoder = IRFFAudioDecoder.decoder(codecContext: codecContextPointer, timebase: 0.001, delegate: fallbackDecoder)
            var samplingRate: Float64 = -1
            var channelCount: UInt32 = 99

            fallbackDecoder.audioDecoder(audioDecoder, samplingRate: &samplingRate)
            fallbackDecoder.audioDecoder(audioDecoder, channelCount: &channelCount)

            XCTAssertEqual(samplingRate, 0)
            XCTAssertEqual(channelCount, 0)
        }
    }

    func testVideoDataSourceCallbacksForwardToSourceOrDefaultToFalseAndNil() {
        var codecContext = AVCodecContext()
        let packet = AVPacket()
        let frame = IRFFVideoFrame()
        let source = DecoderVideoDataSourceSpy(shouldHandle: true, frame: frame)
        let decoder = makeDecoder()
        decoder.source = source

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let info = IRFFVideoDecoderInfo(
                codecContext: codecContextPointer,
                videoToolBoxEnable: false,
                maxDecodeDuration: 1,
                timebase: 0.25,
                fps: 30
            )

            XCTAssertTrue(decoder.shouldHandle(info, decodeFrame: packet))
            XCTAssertTrue(decoder.videoDecoder(info, decodeFrame: packet) === frame)
            XCTAssertEqual(source.shouldHandleCallCount, 1)
            XCTAssertEqual(source.decodeFrameCallCount, 1)

            decoder.source = nil
            XCTAssertFalse(decoder.shouldHandle(info, decodeFrame: packet))
            XCTAssertNil(decoder.videoDecoder(info, decodeFrame: packet))
        }
    }

    func testVideoDecoderErrorStoresErrorAndNotifiesDelegate() {
        let delegate = DecoderDelegateSpy()
        let decoder = makeDecoder()
        decoder.delegate = delegate
        var codecContext = AVCodecContext()
        let error = NSError(domain: "video-decoder-test", code: 17)

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let videoDecoder = IRFFVideoDecoder(codecContext: codecContextPointer, timebase: 0.25, fps: 30, delegate: nil)

            decoder.videoDecoder(videoDecoder, didError: error)
        }

        XCTAssertEqual(decoder.error as NSError?, error)
        XCTAssertEqual(delegate.errors.map(\.code), [17])
        XCTAssertEqual(delegate.errors.map(\.domain), ["video-decoder-test"])
    }

    func testVideoDecoderDelegateMaintenanceCallbacksAreSafeWithoutFormatContext() {
        let decoder = makeDecoder()
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let videoDecoder = IRFFVideoDecoder(codecContext: codecContextPointer, timebase: 0.25, fps: 30, delegate: nil)

            decoder.videoDecoderNeedUpdateBufferedDuration(videoDecoder)
            decoder.videoDecoderNeedCheckBufferingStatus(videoDecoder)
        }

        XCTAssertEqual(decoder.bufferedDuration, 0)
        XCTAssertTrue(decoder.buffering)
    }

    func testVideoFrameOutputCallbackIsSafeWhenVideoDecoderIsMissing() {
        let decoder = makeDecoder()

        decoder.send(videoFrame: IRFFVideoFrame())
    }
}

private func makeDecoder(audioOutput: IRFFDecoderAudioOutput? = nil) -> IRFFDecoder {
    IRFFDecoder(
        contentURL: URL(fileURLWithPath: "/tmp/decoder-operation-test.mp4"),
        videoFormat: .mpeg4,
        videoOutput: nil,
        audioOutput: audioOutput
    )
}

private final class SeekableFFDecoder: IRFFDecoder {
    private let fixedDuration: TimeInterval

    init(duration: TimeInterval) {
        self.fixedDuration = duration
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/seekable-decoder.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override var duration: TimeInterval {
        fixedDuration
    }
}

private final class DecoderDelegateSpy: IRFFDecoderDelegate {
    var onError: (() -> Void)?
    var onPrepared: (() -> Void)?
    var onEndOfFile: (() -> Void)?
    private(set) var willOpenCount = 0
    private(set) var preparedCount = 0
    private(set) var endOfFileCount = 0
    private(set) var playbackFinishedCount = 0
    private(set) var errors: [NSError] = []
    private(set) var bufferingValues: [Bool] = []
    private(set) var bufferedDurations: [TimeInterval] = []
    private(set) var progressValues: [TimeInterval] = []

    func decoderWillOpenInputStream(_ decoder: IRFFDecoder) {
        willOpenCount += 1
    }

    func decoderDidPrepareToDecodeFrames(_ decoder: IRFFDecoder) {
        preparedCount += 1
        onPrepared?()
    }

    func decoderDidEndOfFile(_ decoder: IRFFDecoder) {
        endOfFileCount += 1
        onEndOfFile?()
    }

    func decoderDidPlaybackFinished(_ decoder: IRFFDecoder) {
        playbackFinishedCount += 1
    }

    func decoder(_ decoder: IRFFDecoder, didError error: Error) {
        errors.append(error as NSError)
        onError?()
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBuffering buffering: Bool) {
        bufferingValues.append(buffering)
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfBufferedDuration bufferedDuration: TimeInterval) {
        bufferedDurations.append(bufferedDuration)
    }

    func decoder(_ decoder: IRFFDecoder, didChangeValueOfProgress progress: TimeInterval) {
        progressValues.append(progress)
    }
}

private final class DecoderAudioOutputSpy: IRFFDecoderAudioOutput {
    let numberOfChannels: UInt32
    let samplingRate: Float64

    init(numberOfChannels: UInt32, samplingRate: Float64) {
        self.numberOfChannels = numberOfChannels
        self.samplingRate = samplingRate
    }
}

private final class DecoderVideoOutputSpy: NSObject, IRFFDecoderVideoOutput {
    private(set) var receivedFrames: [IRFFVideoFrame] = []
    var onFirstFrame: (() -> Void)?

    func send(videoFrame frame: IRFFVideoFrame) {
        receivedFrames.append(frame)
        if receivedFrames.count == 1 {
            onFirstFrame?()
        }
    }
}

private final class DecoderVideoDataSourceSpy: IRFFVideoDecoderDataSource {
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
