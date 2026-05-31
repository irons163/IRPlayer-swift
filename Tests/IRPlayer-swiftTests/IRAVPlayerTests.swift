import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAVPlayerTests: XCTestCase {

    func testTrackNameFallsBackWhenLanguageCodeIsMissingOrEmpty() {
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: nil, trackID: 7), "Track 7")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "", trackID: 8), "Track 8")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "  ", trackID: 9), "Track 9")
        XCTAssertEqual(IRAVPlayer.trackName(languageCode: "en", trackID: 10), "en")
    }

    func testMediaSelectionTrackIDParsesOptionPropertyLists() {
        XCTAssertEqual(IRAVPlayer.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 42
        ]), 42)
        XCTAssertEqual(IRAVPlayer.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: NSNumber(value: 43)
        ]), 43)
        XCTAssertNil(IRAVPlayer.mediaSelectionTrackID(from: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: "44"
        ]))
        XCTAssertNil(IRAVPlayer.mediaSelectionTrackID(from: "not-a-dictionary"))
    }

    func testDefaultTrackFallsBackWhenPropertyListDoesNotMatch() {
        let first = IRPlayerTrack()
        first.index = 1
        let second = IRPlayerTrack()
        second.index = 2

        XCTAssertTrue(IRAVPlayer.defaultTrack(from: [first, second], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 2
        ]) === second)
        XCTAssertTrue(IRAVPlayer.defaultTrack(from: [first, second], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: "2"
        ]) === first)
        XCTAssertTrue(IRAVPlayer.defaultTrack(from: [first, second], propertyList: nil) === first)
        XCTAssertNil(IRAVPlayer.defaultTrack(from: [], propertyList: [
            IRAVPlayer.avMediaSelectionOptionTrackIDKey: 2
        ]))
    }

    func testSeekTimeConvertsFiniteNonNegativeSeconds() throws {
        let time = try XCTUnwrap(IRAVPlayer.seekTime(for: 1.25))

        XCTAssertTrue(time.isValid)
        XCTAssertEqual(CMTimeGetSeconds(time), 1.25, accuracy: 0.0001)
    }

    func testSeekTimeRejectsInvalidSeconds() {
        XCTAssertNil(IRAVPlayer.seekTime(for: -0.1))
        XCTAssertNil(IRAVPlayer.seekTime(for: .nan))
        XCTAssertNil(IRAVPlayer.seekTime(for: .infinity))
    }

    func testFiniteSecondsReturnsSecondsForFiniteTime() {
        let time = CMTimeMakeWithSeconds(2.5, preferredTimescale: 1_000)

        XCTAssertEqual(IRAVPlayer.finiteSeconds(from: time), 2.5, accuracy: 0.0001)
    }

    func testFiniteSecondsDefaultsInvalidTimesToZero() {
        XCTAssertEqual(IRAVPlayer.finiteSeconds(from: .invalid), 0)
        XCTAssertEqual(IRAVPlayer.finiteSeconds(from: .indefinite), 0)
        XCTAssertEqual(IRAVPlayer.finiteSeconds(from: CMTime(value: 1, timescale: 0)), 0)
    }

    func testPlayableTimePolicyClampsBufferedRangeToDuration() {
        XCTAssertEqual(IRAVPlayer.playableEndTime(start: 2, duration: 3, totalDuration: 10), 5)
        XCTAssertEqual(IRAVPlayer.playableEndTime(start: 8, duration: 5, totalDuration: 10), 10)
        XCTAssertEqual(IRAVPlayer.playableEndTime(start: -2, duration: 1, totalDuration: 10), 0)
        XCTAssertEqual(IRAVPlayer.playableEndTime(start: TimeInterval.greatestFiniteMagnitude,
                                                 duration: TimeInterval.greatestFiniteMagnitude,
                                                 totalDuration: 10), 0)
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
        let errorInfo = IRAVPlayer.playbackErrorInfo(playerItem: nil, player: nil)

        XCTAssertEqual(errorInfo.error.domain, "AVPlayer playback error")
        XCTAssertEqual(errorInfo.error.code, -1)
    }

    func testItemStatusPolicyMapsAVPlayerItemStatusesToPlaybackDecisions() {
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .unknown, currentState: .none),
            .buffer
        )
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .readyToPlay, currentState: .none),
            .markReady
        )
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .readyToPlay, currentState: .buffering),
            .playIfNeeded
        )
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .readyToPlay, currentState: .failed),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayer.itemStatusDecision(status: .failed, currentState: .playing),
            .fail
        )
    }

    func testPlayStateTransitionMapsCurrentPlaybackState() {
        XCTAssertEqual(IRAVPlayer.nextStateAfterPlay(from: .none), .buffering)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPlay(from: .suspend), .playing)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPlay(from: .readyToPlay), .playing)
        XCTAssertNil(IRAVPlayer.nextStateAfterPlay(from: .buffering))
        XCTAssertNil(IRAVPlayer.nextStateAfterPlay(from: .playing))
        XCTAssertNil(IRAVPlayer.nextStateAfterPlay(from: .finished))
        XCTAssertNil(IRAVPlayer.nextStateAfterPlay(from: .failed))
    }

    func testPauseStateTransitionSuspendsEveryNonFailedPlaybackState() {
        XCTAssertEqual(IRAVPlayer.nextStateAfterPause(from: .none), .suspend)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPause(from: .buffering), .suspend)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPause(from: .playing), .suspend)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPause(from: .readyToPlay), .suspend)
        XCTAssertEqual(IRAVPlayer.nextStateAfterPause(from: .finished), .suspend)
        XCTAssertNil(IRAVPlayer.nextStateAfterPause(from: .failed))
    }

    func testDelayedPlayRetryOnlyRunsForActiveOrReadyStates() {
        XCTAssertTrue(IRAVPlayer.shouldRetryPlayAfterDelay(for: .buffering))
        XCTAssertTrue(IRAVPlayer.shouldRetryPlayAfterDelay(for: .playing))
        XCTAssertTrue(IRAVPlayer.shouldRetryPlayAfterDelay(for: .readyToPlay))
        XCTAssertFalse(IRAVPlayer.shouldRetryPlayAfterDelay(for: .none))
        XCTAssertFalse(IRAVPlayer.shouldRetryPlayAfterDelay(for: .suspend))
        XCTAssertFalse(IRAVPlayer.shouldRetryPlayAfterDelay(for: .finished))
        XCTAssertFalse(IRAVPlayer.shouldRetryPlayAfterDelay(for: .failed))
    }

    func testActivePlaybackStatePolicyIncludesOnlyBufferingAndPlaying() {
        XCTAssertTrue(IRAVPlayer.isActivePlaybackState(.buffering))
        XCTAssertTrue(IRAVPlayer.isActivePlaybackState(.playing))
        XCTAssertFalse(IRAVPlayer.isActivePlaybackState(.none))
        XCTAssertFalse(IRAVPlayer.isActivePlaybackState(.readyToPlay))
        XCTAssertFalse(IRAVPlayer.isActivePlaybackState(.suspend))
        XCTAssertFalse(IRAVPlayer.isActivePlaybackState(.finished))
        XCTAssertFalse(IRAVPlayer.isActivePlaybackState(.failed))
    }

    func testAVAssetLoadDecisionFailsWhenAnyRequiredKeyFails() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(keyStatuses: [.loaded, .failed], trackStatus: .loaded),
            .fail
        )
    }

    func testAVAssetLoadDecisionSetsUpOutputWhenTracksAreLoaded() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: .loaded),
            .setupOutput
        )
    }

    func testAVAssetLoadDecisionIgnoresIncompleteTrackStatus() {
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: .loading),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayer.avAssetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: nil),
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
