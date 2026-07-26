import Foundation
import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFPlayerTests: XCTestCase {

    func testFactoryCreatesPlayerWhenAudioManagerIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil

        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)

        XCTAssertNil(ffPlayer.audioManager)
        XCTAssertEqual(ffPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReleaseDoesNotPrintDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        var ffPlayer: IRFFPlayer? = IRFFPlayer.player(with: abstractPlayer)
        XCTAssertNotNil(ffPlayer)

        let output = captureStandardOutput {
            ffPlayer = nil
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayableBufferIntervalReloadsFFmpegDecoderBufferDuration() throws {
        let player = IRPlayerImp.player()
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
        player.manager = nil
        player.replaceVideoWithURL(contentURL: NSURL(fileURLWithPath: "/tmp/missing.flv"))

        let ffPlayer = try XCTUnwrap(loadedFFPlayer(from: player))
        addTeardownBlock {
            ffPlayer.stop()
        }
        let decoder = try XCTUnwrap(ffPlayer.decoder)
        XCTAssertEqual(decoder.minBufferedDuration, 2)

        player.playableBufferInterval = 7

        XCTAssertEqual(decoder.minBufferedDuration, 7)
        withExtendedLifetime(player) {}
    }

    func testPlayableTimePostsNotificationWhenBufferedTimeChangesWithinDuration() throws {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        ffPlayer.decoder = FixedDurationFFDecoder(duration: 10)

        let expectation = expectation(description: "playable notification")
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(IRPlayerPlayableChangeNotificationName),
            object: abstractPlayer,
            queue: .main
        ) { notification in
            let playable = IRModel.playable(fromUserInfo: notification.userInfo ?? [:])
            XCTAssertEqual(playable.current, 4, accuracy: 0.0001)
            XCTAssertEqual(playable.total, 10, accuracy: 0.0001)
            expectation.fulfill()
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(observer)
        }

        ffPlayer.playableTime = 4

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayableTimeClampsToDecoderDuration() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        ffPlayer.decoder = FixedDurationFFDecoder(duration: 10)

        ffPlayer.playableTime = 15

        XCTAssertEqual(ffPlayer.playableTime, 10)
    }

    func testPresentationSizeAndBitrateRequirePreparedDecoder() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let decoder = PreparedMetricsFFDecoder(
            duration: 10,
            presentationSize: CGSize(width: 1920, height: 1080),
            bitrate: 640
        )
        ffPlayer.decoder = decoder

        XCTAssertEqual(ffPlayer.presentationSize, .zero)
        XCTAssertEqual(ffPlayer.bitrate, 0)

        decoder.setValue(true, forKey: "prepareToDecode")

        XCTAssertEqual(ffPlayer.presentationSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(ffPlayer.bitrate, 640)
    }

    func testAudioCopyPlanRejectsInvalidFrameOffsets() {
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: -1, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 129, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 0, remainingFrames: 32, numberOfChannels: 0))
    }

    func testAudioCopyPlanRejectsUnalignedFrameOffsets() {
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 1, remainingFrames: 32, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 4, remainingFrames: 32, numberOfChannels: 2))
    }

    func testAudioCopyPlanRejectsOverflowingFrameCalculations() {
        XCTAssertNil(
            IRFFPlayer.audioCopyPlan(
                frameSize: Int.max,
                outputOffset: 0,
                remainingFrames: .max,
                numberOfChannels: .max
            )
        )
    }

    func testAudioSilenceByteCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 0, numberOfChannels: 2))
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 0))
        XCTAssertNil(IRFFPlayer.audioSilenceByteCount(numberOfFrames: .max, numberOfChannels: .max))
    }

    func testAudioSilenceByteCountCalculatesFloatStorageSize() {
        XCTAssertEqual(IRFFPlayer.audioSilenceByteCount(numberOfFrames: 10, numberOfChannels: 2), 80)
    }

    func testAudioCopyPlanCalculatesFramesAndBytesWithinBounds() throws {
        let partial = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 0, remainingFrames: 10, numberOfChannels: 2)
        )
        XCTAssertEqual(partial.bytesToCopy, 80)
        XCTAssertEqual(partial.framesToCopy, 10)
        XCTAssertTrue(partial.hasRemainingFrameBytes)

        let final = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 128, outputOffset: 120, remainingFrames: 10, numberOfChannels: 2)
        )
        XCTAssertEqual(final.bytesToCopy, 8)
        XCTAssertEqual(final.framesToCopy, 1)
        XCTAssertFalse(final.hasRemainingFrameBytes)
    }

    func testAudioCopyPlanCopiesOnlyWholeFrames() throws {
        let plan = try XCTUnwrap(
            IRFFPlayer.audioCopyPlan(frameSize: 10, outputOffset: 0, remainingFrames: 2, numberOfChannels: 2)
        )

        XCTAssertEqual(plan.bytesToCopy, 8)
        XCTAssertEqual(plan.framesToCopy, 1)
        XCTAssertTrue(plan.hasRemainingFrameBytes)
    }

    func testAudioOutputWritesSilenceWhenNotPlaying() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        var output = [Float](repeating: 7, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testAudioOutputWritesSilenceWhenPlayingWithoutAudioFrame() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        ffPlayer.playing = true
        var output = [Float](repeating: -3, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testAudioOutputStopsFrameAndSilencesWhenSamplesAreMissing() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let frame = IRFFAudioFrame()
        ffPlayer.playing = true
        ffPlayer.currentAudioFrame = frame
        var output = [Float](repeating: 4, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertNil(ffPlayer.currentAudioFrame)
        XCTAssertFalse(frame.playing)
        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testAudioOutputClearsInvalidLeaseAndSilencesWithoutMutatingFrameLifecycle() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let frame = makeAudioFrame(samples: [1, 2, 3, 4])
        frame.outputOffset = 1
        ffPlayer.playing = true
        ffPlayer.currentAudioFrame = frame
        var output = [Float](repeating: 4, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertNil(ffPlayer.currentAudioFrame)
        XCTAssertTrue(frame.playing)
        XCTAssertEqual(output, [0, 0, 0, 0])
    }

    func testAudioOutputFetchesFrameFromDecoderWhenCurrentFrameIsMissing() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let frame = makeAudioFrame(samples: [1, 2, 3, 4])
        frame.stopPlaying()
        let decoder = AudioFrameFFDecoder(frame: frame)
        ffPlayer.decoder = decoder
        ffPlayer.playing = true
        var output = [Float](repeating: 0, count: 2)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(decoder.fetchCount, 1)
        XCTAssertEqual(output, [1, 2])
        XCTAssertTrue(ffPlayer.currentAudioFrame === frame)
        XCTAssertFalse(frame.playing)
    }

    func testAudioOutputCopiesPartialFrameAndPreservesRemainingOffset() throws {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let frame = makeAudioFrame(samples: [1, 2, 3, 4])
        ffPlayer.playing = true
        ffPlayer.currentAudioFrame = frame
        var output = [Float](repeating: 0, count: 2)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 1,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [1, 2])
        XCTAssertTrue(ffPlayer.currentAudioFrame === frame)
        XCTAssertEqual(frame.outputOffset, 0)
    }

    func testAudioOutputCopiesFinalFrameAndClearsLeaseWithoutMutatingFrameLifecycle() throws {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let frame = makeAudioFrame(samples: [1, 2, 3, 4])
        frame.outputOffset = MemoryLayout<Float>.size * 2
        ffPlayer.playing = true
        ffPlayer.currentAudioFrame = frame
        var output = [Float](repeating: 0, count: 4)

        output.withUnsafeMutableBufferPointer { buffer in
            ffPlayer.audioRenderer.audioManager(
                makeTestAudioManager(),
                outputData: buffer.baseAddress!,
                numberOfFrames: 2,
                numberOfChannels: 2
            )
        }

        XCTAssertEqual(output, [3, 4, 0, 0])
        XCTAssertNil(ffPlayer.currentAudioFrame)
        XCTAssertTrue(frame.playing)
    }

    func testAudioOutputPropertiesReturnZeroWithoutAudioManager() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()

        XCTAssertEqual(ffPlayer.samplingRate, 0)
        XCTAssertEqual(ffPlayer.numberOfChannels, 0)
    }

    func testFFPlayerUsesDedicatedRendererAndStopsItBeforeDecoderClose() {
        let driver = TestAudioGraphDriver()
        let manager = makeTestAudioManager(driver: driver)
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = manager
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        var closeObservations: [String] = []
        let decoder = CloseObservingFFDecoder {
            closeObservations.append("decoder")
            XCTAssertFalse(manager.playing)
            XCTAssertFalse(ffPlayer.audioRenderer.diagnostics.enabled)
            XCTAssertFalse(ffPlayer.audioRenderer.diagnostics.hasSource)
            XCTAssertEqual(driver.stopCount, 1)
        }
        ffPlayer.decoder = decoder
        ffPlayer.playing = true
        ffPlayer.state = .playing

        XCTAssertTrue(manager.delegate === ffPlayer.audioRenderer)
        XCTAssertTrue(manager.playing)

        ffPlayer.stop()

        XCTAssertEqual(closeObservations, ["decoder"])
        XCTAssertFalse(manager.playing)
        XCTAssertNil(manager.delegate)
        XCTAssertNil(ffPlayer.decoder)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlaybackCommandsUpdateStateWithoutDecoder() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        ffPlayer.state = .finished

        ffPlayer.play()

        XCTAssertTrue(ffPlayer.playing)
        XCTAssertEqual(ffPlayer.state, .playing)

        ffPlayer.pause()

        XCTAssertFalse(ffPlayer.playing)
        XCTAssertEqual(ffPlayer.state, .suspend)

        ffPlayer.seek(to: 3)
        var seekResult: Bool?
        ffPlayer.seek(to: 4) { didFinish in
            seekResult = didFinish
        }
        XCTAssertEqual(seekResult, false)
    }

    func testDecoderDelegateCallbacksUpdatePlaybackStateAndProgress() throws {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        let decoder = FixedDurationFFDecoder(duration: 10)
        ffPlayer.decoder = decoder
        let delegate = try XCTUnwrap(decoder.delegate)
        ffPlayer.playing = true
        ffPlayer.progress = 2

        delegate.decoderWillOpenInputStream(decoder)
        XCTAssertEqual(ffPlayer.state, .buffering)

        delegate.decoderDidPrepareToDecodeFrames(decoder)
        XCTAssertEqual(ffPlayer.state, .readyToPlay)

        delegate.decoder(decoder, didChangeValueOfBuffering: false)
        XCTAssertEqual(ffPlayer.state, .playing)

        delegate.decoder(decoder, didChangeValueOfBufferedDuration: 3)
        XCTAssertEqual(ffPlayer.playableTime, 5)

        delegate.decoder(decoder, didChangeValueOfProgress: 4)
        XCTAssertEqual(ffPlayer.progress, 4)

        delegate.decoderDidEndOfFile(decoder)
        XCTAssertEqual(ffPlayer.playableTime, 10)

        delegate.decoderDidPlaybackFinished(decoder)
        XCTAssertEqual(ffPlayer.state, .finished)

        withExtendedLifetime(abstractPlayer) {}
    }

    func testDecoderErrorStoresPlayerErrorAndFailsState() throws {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        let decoder = FixedDurationFFDecoder(duration: 10)
        let error = NSError(domain: "ff-test", code: 9)
        ffPlayer.decoder = decoder
        let delegate = try XCTUnwrap(decoder.delegate)

        delegate.decoder(decoder, didError: error)

        XCTAssertEqual(ffPlayer.state, .failed)
        XCTAssertEqual(abstractPlayer.error?.error.domain, "ff-test")
        XCTAssertEqual(abstractPlayer.error?.error.code, 9)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testLiveStreamPlayableBufferIntervalIsCappedAndDefaulted() {
        let abstractPlayer = IRPlayerImp.player()
        abstractPlayer.manager = nil
        abstractPlayer.isLiveStream = true
        abstractPlayer.playableBufferInterval = 7
        let ffPlayer = IRFFPlayer.player(with: abstractPlayer)
        let decoder = FixedDurationFFDecoder(duration: 0)
        ffPlayer.decoder = decoder

        ffPlayer.reloadPlayableBufferInterval()
        XCTAssertTrue(decoder.isLiveStream)
        XCTAssertEqual(decoder.minBufferedDuration, 0.2, accuracy: 0.0001)

        abstractPlayer.playableBufferInterval = 0
        ffPlayer.reloadPlayableBufferInterval()
        XCTAssertEqual(decoder.minBufferedDuration, 0.2, accuracy: 0.0001)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayableBufferIntervalDefaultsWhenAbstractPlayerIsReleased() {
        let ffPlayer = makeFFPlayerWithoutAudioManager()
        let decoder = FixedDurationFFDecoder(duration: 10)
        decoder.isLiveStream = true
        decoder.minBufferedDuration = 7
        ffPlayer.decoder = decoder

        ffPlayer.reloadPlayableBufferInterval()

        XCTAssertFalse(decoder.isLiveStream)
        XCTAssertEqual(decoder.minBufferedDuration, 0)
    }

    func testStaticCompatibilityWrappersUseRuntimeOwnerPolicies() {
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: false),
            .missingDisplayView
        )
        XCTAssertEqual(
            IRFFPlayer.playTransition(from: .finished),
            IRFFPlayerStateMachine.playTransition(from: .finished)
        )
        XCTAssertEqual(
            IRFFPlayer.pauseTransition(from: .playing),
            IRFFPlayerStateMachine.pauseTransition(from: .playing)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayerStateMachine.bufferingTransition(
                isBuffering: false,
                isPlaying: false,
                hasPreparedOnce: false
            )
        )
        XCTAssertEqual(
            IRFFPlayer.audioSilenceByteCount(
                numberOfFrames: 10,
                numberOfChannels: 2
            ),
            IRFFAudioRenderer.silenceByteCount(
                numberOfFrames: 10,
                numberOfChannels: 2
            )
        )
    }

    func testReplaceVideoReadinessDistinguishesNoOpAndFailurePreconditions() {
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: false, hasContentURL: true, hasDisplayView: true),
            .missingRequiredInput
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: false, hasDisplayView: true),
            .missingRequiredInput
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: false),
            .missingDisplayView
        )
        XCTAssertEqual(
            IRFFPlayer.replaceVideoReadiness(hasAbstractPlayer: true, hasContentURL: true, hasDisplayView: true),
            .ready
        )
    }

    func testPlayTransitionMapsCurrentStateToNextStateAndSeekDecision() {
        XCTAssertEqual(IRFFPlayer.playTransition(from: .finished), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: true))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .none), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .failed), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .buffering), IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .readyToPlay), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .playing), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
        XCTAssertEqual(IRFFPlayer.playTransition(from: .suspend), IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false))
    }

    func testPauseTransitionSuspendsOnlyActiveOrTerminalPlaybackStates() {
        XCTAssertNil(IRFFPlayer.pauseTransition(from: .none))
        XCTAssertNil(IRFFPlayer.pauseTransition(from: .suspend))
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .failed), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .readyToPlay), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .finished), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .playing), .suspend)
        XCTAssertEqual(IRFFPlayer.pauseTransition(from: .buffering), .suspend)
    }

    func testBufferingTransitionMapsDecoderBufferingStateAndPrepareToken() {
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: true, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .buffering, hasPreparedOnce: false)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: true, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .playing, hasPreparedOnce: false)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: false),
            IRFFPlayer.BufferingTransition(nextState: .readyToPlay, hasPreparedOnce: true)
        )
        XCTAssertEqual(
            IRFFPlayer.bufferingTransition(isBuffering: false, isPlaying: false, hasPreparedOnce: true),
            IRFFPlayer.BufferingTransition(nextState: .suspend, hasPreparedOnce: true)
        )
    }

}

private func makeFFPlayerWithoutAudioManager() -> IRFFPlayer {
    let abstractPlayer = IRPlayerImp.player()
    abstractPlayer.manager = nil
    return IRFFPlayer.player(with: abstractPlayer)
}

private func makeAudioFrame(samples values: [Float]) -> IRFFAudioFrame {
    let frame = IRFFAudioFrame()
    frame.setSamplesLength(values.count * MemoryLayout<Float>.size)
    frame.withMutableSamples { samples in
        for (index, value) in values.enumerated() {
            samples[index] = value
        }
        return true
    }
    frame.startPlaying()
    return frame
}

private final class FixedDurationFFDecoder: IRFFDecoder {
    private let fixedDuration: TimeInterval

    init(duration: TimeInterval) {
        self.fixedDuration = duration
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/fixed-duration.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override var duration: TimeInterval {
        fixedDuration
    }
}

private final class PreparedMetricsFFDecoder: IRFFDecoder {
    private let fixedDuration: TimeInterval
    private let fixedPresentationSize: CGSize
    private let fixedBitrate: TimeInterval

    init(duration: TimeInterval, presentationSize: CGSize, bitrate: TimeInterval) {
        self.fixedDuration = duration
        self.fixedPresentationSize = presentationSize
        self.fixedBitrate = bitrate
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/prepared-metrics.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override var duration: TimeInterval {
        fixedDuration
    }

    override var presentationSize: CGSize {
        fixedPresentationSize
    }

    override var bitrate: TimeInterval {
        fixedBitrate
    }
}

private final class AudioFrameFFDecoder: IRFFDecoder {
    private let frame: IRFFAudioFrame?
    private(set) var fetchCount = 0

    init(frame: IRFFAudioFrame?) {
        self.frame = frame
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/audio-frame.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override func fetchAudioFrame() -> IRFFAudioRenderLease? {
        fetchCount += 1
        guard let frame else { return nil }
        return IRFFAudioRenderLease(
            frame: frame,
            byteCount: frame.size
        )
    }
}

private final class CloseObservingFFDecoder: IRFFDecoder {
    private let onClose: () -> Void
    private var didClose = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/close-order.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
    }

    override func closeFile() {
        guard !didClose else { return }
        didClose = true
        onClose()
    }
}
