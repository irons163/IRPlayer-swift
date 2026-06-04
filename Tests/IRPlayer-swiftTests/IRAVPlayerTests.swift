import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAVPlayerTests: XCTestCase {

    func testTrackNameFallsBackWhenLanguageCodeIsMissingOrEmpty() {
        XCTAssertEqual(IRAVPlayerTrackPolicy.trackName(languageCode: nil, trackID: 7), "Track 7")
        XCTAssertEqual(IRAVPlayerTrackPolicy.trackName(languageCode: "", trackID: 8), "Track 8")
        XCTAssertEqual(IRAVPlayerTrackPolicy.trackName(languageCode: "  ", trackID: 9), "Track 9")
        XCTAssertEqual(IRAVPlayerTrackPolicy.trackName(languageCode: "en", trackID: 10), "en")
    }

    func testMediaSelectionTrackIDParsesOptionPropertyLists() {
        XCTAssertEqual(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 42
        ]), 42)
        XCTAssertEqual(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: NSNumber(value: 43)
        ]), 43)
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: "44"
        ]))
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: "not-a-dictionary"))
    }

    func testMediaSelectionTrackIDRejectsMalformedNumericPropertyLists() {
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: NSNumber(value: true)
        ]))
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: NSNumber(value: 1.5)
        ]))
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: NSNumber(value: UInt64.max)
        ]))
    }

    func testDefaultTrackFallsBackWhenPropertyListDoesNotMatch() {
        let first = IRPlayerTrack()
        first.index = 1
        let second = IRPlayerTrack()
        second.index = 2

        XCTAssertTrue(IRAVPlayerTrackPolicy.defaultTrack(from: [first, second], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 2
        ]) === second)
        XCTAssertTrue(IRAVPlayerTrackPolicy.defaultTrack(from: [first, second], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: "2"
        ]) === first)
        XCTAssertTrue(IRAVPlayerTrackPolicy.defaultTrack(from: [first, second], propertyList: nil) === first)
        XCTAssertNil(IRAVPlayerTrackPolicy.defaultTrack(from: [], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 2
        ]))
    }

    func testSeekTimeConvertsFiniteNonNegativeSeconds() throws {
        let time = try XCTUnwrap(IRAVPlayerTimePolicy.seekTime(for: 1.25))

        XCTAssertTrue(time.isValid)
        XCTAssertEqual(CMTimeGetSeconds(time), 1.25, accuracy: 0.0001)
    }

    func testSeekTimeRejectsInvalidSeconds() {
        XCTAssertNil(IRAVPlayerTimePolicy.seekTime(for: -0.1))
        XCTAssertNil(IRAVPlayerTimePolicy.seekTime(for: .nan))
        XCTAssertNil(IRAVPlayerTimePolicy.seekTime(for: .infinity))
    }

    func testFiniteSecondsReturnsSecondsForFiniteTime() {
        let time = CMTimeMakeWithSeconds(2.5, preferredTimescale: 1_000)

        XCTAssertEqual(IRAVPlayerTimePolicy.finiteSeconds(from: time), 2.5, accuracy: 0.0001)
    }

    func testFiniteSecondsDefaultsInvalidTimesToZero() {
        XCTAssertEqual(IRAVPlayerTimePolicy.finiteSeconds(from: .invalid), 0)
        XCTAssertEqual(IRAVPlayerTimePolicy.finiteSeconds(from: .indefinite), 0)
        XCTAssertEqual(IRAVPlayerTimePolicy.finiteSeconds(from: CMTime(value: 1, timescale: 0)), 0)
    }

    func testPlayableTimePolicyClampsBufferedRangeToDuration() {
        XCTAssertEqual(IRAVPlayerTimePolicy.playableEndTime(start: 2, duration: 3, totalDuration: 10), 5)
        XCTAssertEqual(IRAVPlayerTimePolicy.playableEndTime(start: 8, duration: 5, totalDuration: 10), 10)
        XCTAssertEqual(IRAVPlayerTimePolicy.playableEndTime(start: -2, duration: 1, totalDuration: 10), 0)
        XCTAssertEqual(IRAVPlayerTimePolicy.playableEndTime(start: TimeInterval.greatestFiniteMagnitude,
                                                 duration: TimeInterval.greatestFiniteMagnitude,
                                                 totalDuration: 10), 0)
    }

    func testStaticPolicyWrappersRemainSourceCompatible() throws {
        let first = IRPlayerTrack()
        first.index = 1
        let second = IRPlayerTrack()
        second.index = 2
        let propertyList = [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 2
        ]
        let finiteTime = CMTimeMakeWithSeconds(2.5, preferredTimescale: 1_000)

        XCTAssertEqual(
            IRAVPlayer.trackName(languageCode: nil, trackID: 7),
            IRAVPlayerTrackPolicy.trackName(languageCode: nil, trackID: 7)
        )
        XCTAssertEqual(
            IRAVPlayer.mediaSelectionTrackID(from: propertyList),
            IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: propertyList)
        )
        XCTAssertTrue(
            IRAVPlayer.defaultTrack(from: [first, second], propertyList: propertyList) ===
            IRAVPlayerTrackPolicy.defaultTrack(from: [first, second], propertyList: propertyList)
        )
        XCTAssertEqual(
            CMTimeGetSeconds(try XCTUnwrap(IRAVPlayer.seekTime(for: 1.25))),
            CMTimeGetSeconds(try XCTUnwrap(IRAVPlayerTimePolicy.seekTime(for: 1.25))),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRAVPlayer.finiteSeconds(from: finiteTime),
            IRAVPlayerTimePolicy.finiteSeconds(from: finiteTime),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRAVPlayer.playableEndTime(start: 2, duration: 3, totalDuration: 10),
            IRAVPlayerTimePolicy.playableEndTime(start: 2, duration: 3, totalDuration: 10)
        )
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .readyToPlay, currentState: .none),
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .readyToPlay, currentState: .none)
        )
        XCTAssertEqual(
            IRAVPlayer.nextStateAfterPlay(from: .none),
            IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .none)
        )
        XCTAssertEqual(
            IRAVPlayer.nextStateAfterPause(from: .playing),
            IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .playing)
        )
        XCTAssertEqual(
            IRAVPlayer.shouldRetryPlayAfterDelay(for: .buffering),
            IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .buffering)
        )
        XCTAssertEqual(
            IRAVPlayer.isActivePlaybackState(.playing),
            IRAVPlayerPlaybackPolicy.isActivePlaybackState(.playing)
        )
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(keyStatuses: [.loaded, .failed], trackStatus: .loaded),
            IRAVPlayerAssetLoadPolicy.decision(keyStatuses: [.loaded, .failed], trackStatus: .loaded)
        )

        let wrapperError = IRAVPlayer.playbackErrorInfo(playerItem: nil, player: nil)
        let policyError = IRAVPlayerErrorPolicy.playbackErrorInfo(playerItem: nil, player: nil)
        XCTAssertEqual(wrapperError.error.domain, policyError.error.domain)
        XCTAssertEqual(wrapperError.error.code, policyError.error.code)
    }

    func testSetupAVPlayerItemIgnoresMissingAsset() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avAsset = nil
        avPlayer.setupAVPlayerItem(autoLoadedAsset: false)

        XCTAssertNil(avPlayer.avPlayerItem)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPauseIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.pause()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSetPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .playing
        avPlayer.avPlayer = nil
        avPlayer.setPlayIfNeeded()

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .buffering
        avPlayer.needPlay = true
        avPlayer.avPlayer = nil
        avPlayer.playIfNeeded()

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSeekIgnoresMissingPlayerItem() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionCalled = false

        avPlayer.avPlayerItem = nil
        avPlayer.seek(to: 1) { _ in
            completionCalled = true
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertFalse(completionCalled)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testCompleteSeekUpdatesStateAndDoesNotPrintDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionResult: Bool?

        avPlayer.seeking = true
        let output = captureStandardOutput {
            avPlayer.completeSeek(finished: true) { finished in
                completionResult = finished
            }
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertEqual(completionResult, true)
        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testProgressReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil

        XCTAssertEqual(avPlayer.progress, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testDurationReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil

        XCTAssertEqual(avPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReloadVolumeIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayer = nil
        avPlayer.reloadVolume()

        XCTAssertNil(avPlayer.avPlayer)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReloadVolumeIgnoresReleasedAbstractPlayer() {
        var retainedPlayer: IRAVPlayer?
        autoreleasepool {
            let abstractPlayer = IRPlayerImp.player()
            let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
            avPlayer.avPlayer = AVPlayer()
            retainedPlayer = avPlayer
        }

        XCTAssertNil(retainedPlayer?.abstractPlayer)
        retainedPlayer?.reloadVolume()
        retainedPlayer?.displayLink?.invalidate()
    }

    func testPlaybackErrorInfoFallsBackWhenPlayerItemAndPlayerAreMissing() {
        let errorInfo = IRAVPlayerErrorPolicy.playbackErrorInfo(playerItem: nil, player: nil)

        XCTAssertEqual(errorInfo.error.domain, "AVPlayer playback error")
        XCTAssertEqual(errorInfo.error.code, -1)
    }

    func testItemStatusPolicyMapsAVPlayerItemStatusesToPlaybackDecisions() {
        XCTAssertEqual(
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .unknown, currentState: .none),
            .buffer
        )
        XCTAssertEqual(
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .readyToPlay, currentState: .none),
            .markReady
        )
        XCTAssertEqual(
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .readyToPlay, currentState: .buffering),
            .playIfNeeded
        )
        XCTAssertEqual(
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .readyToPlay, currentState: .failed),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayerPlaybackPolicy.itemStatusDecision(status: .failed, currentState: .playing),
            .fail
        )
    }

    func testPlayStateTransitionMapsCurrentPlaybackState() {
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .none), .buffering)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .suspend), .playing)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .readyToPlay), .playing)
        XCTAssertNil(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .buffering))
        XCTAssertNil(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .playing))
        XCTAssertNil(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .finished))
        XCTAssertNil(IRAVPlayerPlaybackPolicy.nextStateAfterPlay(from: .failed))
    }

    func testPauseStateTransitionSuspendsEveryNonFailedPlaybackState() {
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .none), .suspend)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .buffering), .suspend)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .playing), .suspend)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .readyToPlay), .suspend)
        XCTAssertEqual(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .finished), .suspend)
        XCTAssertNil(IRAVPlayerPlaybackPolicy.nextStateAfterPause(from: .failed))
    }

    func testDelayedPlayRetryOnlyRunsForActiveOrReadyStates() {
        XCTAssertTrue(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .buffering))
        XCTAssertTrue(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .playing))
        XCTAssertTrue(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .readyToPlay))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .none))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .suspend))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .finished))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.shouldRetryPlayAfterDelay(for: .failed))
    }

    func testActivePlaybackStatePolicyIncludesOnlyBufferingAndPlaying() {
        XCTAssertTrue(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.buffering))
        XCTAssertTrue(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.playing))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.none))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.readyToPlay))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.suspend))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.finished))
        XCTAssertFalse(IRAVPlayerPlaybackPolicy.isActivePlaybackState(.failed))
    }

    func testAVAssetLoadDecisionFailsWhenAnyRequiredKeyFails() {
        XCTAssertEqual(
            IRAVPlayerAssetLoadPolicy.decision(keyStatuses: [.loaded, .failed], trackStatus: .loaded),
            .fail
        )
    }

    func testAVAssetLoadDecisionSetsUpOutputWhenTracksAreLoaded() {
        XCTAssertEqual(
            IRAVPlayerAssetLoadPolicy.decision(keyStatuses: [.loaded, .loaded], trackStatus: .loaded),
            .setupOutput
        )
    }

    func testAVAssetLoadDecisionIgnoresIncompleteTrackStatus() {
        XCTAssertEqual(
            IRAVPlayerAssetLoadPolicy.decision(keyStatuses: [.loaded, .loaded], trackStatus: .loading),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayerAssetLoadPolicy.decision(keyStatuses: [.loaded, .loaded], trackStatus: nil),
            .ignore
        )
    }

    func testUnknownItemStatusBuffersWithoutDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let item = AVPlayerItem(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing.mp4"))

        avPlayer.avPlayerItem = item
        let output = captureStandardOutput {
            avPlayer.observeValue(forKeyPath: "status", of: item, change: nil, context: nil)
        }

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testAVAssetPrepareFailureDoesNotPrintDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let error = NSError(domain: "IRAVPlayerTests", code: 1)

        let output = captureStandardOutput {
            avPlayer.avAssetPrepareFailed(error: error)
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPixelBufferAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil
        avPlayer.avOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [:])

        XCTAssertNil(avPlayer.pixelBufferAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSetupOutputIgnoresMissingPlayerItemWithoutDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avPlayerItem = nil
        let output = captureStandardOutput {
            avPlayer.setupOutput()
        }

        XCTAssertNil(avPlayer.avOutput)
        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSnapshotAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.avAsset = AVURLAsset(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing.mp4"))
        avPlayer.avPlayerItem = nil

        XCTAssertNil(avPlayer.snapshotAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSnapshotAtCurrentTimeReturnsNilWithoutDebugOutputWhenImageGenerationFails() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing.mp4")

        avPlayer.avAsset = AVURLAsset(url: url)
        avPlayer.avPlayerItem = AVPlayerItem(url: url)
        let output = captureStandardOutput {
            XCTAssertNil(avPlayer.snapshotAtCurrentTime())
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }
}
