import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAVPlayerTests: XCTestCase {

    func testDisplayLinkDoesNotRetainPlayerAfterScopeEnds() {
        weak var weakPlayer: IRAVPlayer?

        autoreleasepool {
            let abstractPlayer = IRPlayerImp.player()
            let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
            weakPlayer = avPlayer
        }

        XCTAssertNil(weakPlayer)
    }

    func testDeinitSilentlyClosesResourcesWithoutHostCallbacks() {
        let host = AVPlaybackBackendHostSpy(
            contentURL: missingMediaURL() as NSURL
        )
        host.displayView = IRGLView(frame: .zero)

        autoreleasepool {
            let player = IRAVPlayer(abstractPlayer: host)
            activate(player, url: missingMediaURL())
            host.displayView?.setAVPlayer(player.avPlayer)
            XCTAssertEqual(player.session.diagnostics.phase, .active)
            XCTAssertNotNil(host.displayView?.attachedAVPlayer)
        }
        waitForMainQueue()

        XCTAssertNil(host.displayView?.attachedAVPlayer)
        XCTAssertEqual(host.stateChanges, 0)
        XCTAssertEqual(host.progressUpdates, 0)
        XCTAssertEqual(host.playableUpdates, 0)
        XCTAssertEqual(host.failures, 0)
    }

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
        XCTAssertNil(IRAVPlayerTrackPolicy.mediaSelectionTrackID(from: [:] as [String: Any]))
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
            IRAVPlayerSession.assetLoadDecision(keyStatuses: [.loaded, .failed], trackStatus: .loaded)
        )
        XCTAssertEqual(
            IRAVPlayer.resourceLoaderRedirectRequest(
                for: URLRequest(url: URL(string: "https://example.com/video.m3u8")!),
                headers: ["Authorization": "Bearer token"]
            )?.value(forHTTPHeaderField: "Authorization"),
            IRAVPlayerSession.resourceLoaderRedirectRequest(
                for: URLRequest(url: URL(string: "https://example.com/video.m3u8")!),
                headers: ["Authorization": "Bearer token"]
            )?.value(forHTTPHeaderField: "Authorization")
        )

        let wrapperError = IRAVPlayer.playbackErrorInfo(playerItem: nil, player: nil)
        let policyError = IRAVPlayerErrorPolicy.playbackErrorInfo(playerItem: nil, player: nil)
        XCTAssertEqual(wrapperError.error.domain, policyError.error.domain)
        XCTAssertEqual(wrapperError.error.code, policyError.error.code)
    }

    func testSessionStartsWithoutAVResources() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertNil(avPlayer.avAsset)
        XCTAssertNil(avPlayer.avPlayerItem)
        XCTAssertNil(avPlayer.avPlayer)
        XCTAssertNil(avPlayer.avOutput)
        XCTAssertEqual(avPlayer.session.diagnostics.phase, .empty)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayResetsFinishedPlaybackBeforeReplacement() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .finished
        avPlayer.needPlay = true
        avPlayer.readyToPlayTime = 42

        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .none)
        XCTAssertNil(avPlayer.avPlayer)
        XCTAssertFalse(avPlayer.needPlay)
        XCTAssertFalse(avPlayer.seeking)
        XCTAssertEqual(avPlayer.readyToPlayTime, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testDelayedRetryCannotControlReplacementPlayer() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = try makeTemporaryTinyVideoFile()
        _ = activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        waitUntilReadyToPlay(try XCTUnwrap(avPlayer.avPlayerItem))
        avPlayer.state = .playing

        avPlayer.play()
        avPlayer.replaceEmpty()
        _ = activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        let replacementPlayer = try XCTUnwrap(avPlayer.avPlayer)
        replacementPlayer.pause()
        avPlayer.state = .playing
        waitForMainQueue(after: 0.35)

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertEqual(replacementPlayer.timeControlStatus, .paused)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testAutoPlayFlagsSuspendActivePlaybackAndClearAfterAttempt() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .playing

        avPlayer.setAutoPlayIfNeed()

        XCTAssertEqual(avPlayer.state, .suspend)
        XCTAssertTrue(avPlayer.autoNeedPlay)

        avPlayer.cancelAutoPlayIfNeed()
        XCTAssertFalse(avPlayer.autoNeedPlay)

        avPlayer.autoNeedPlay = true
        avPlayer.autoPlayIfNeed()

        XCTAssertFalse(avPlayer.autoNeedPlay)
        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPauseIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.pause()

        XCTAssertEqual(avPlayer.state, .none)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSetPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .playing
        avPlayer.setPlayIfNeeded()

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testCancelPlayIfNeededClearsPendingPlayFlag() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.needPlay = true

        avPlayer.cancelPlayIfNeeded()

        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlayIfNeededIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.state = .buffering
        avPlayer.needPlay = true
        avPlayer.playIfNeeded()

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSeekRejectsMissingPlayerItemWithFalseCompletion() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionResult: Bool?

        avPlayer.seek(to: 1) {
            completionResult = $0
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertEqual(completionResult, false)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testInvalidSeekDoesNotPrintDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        var completionResult: Bool?

        let output = captureStandardOutput {
            avPlayer.seek(to: .nan) { finished in
                completionResult = finished
            }
        }

        XCTAssertFalse(avPlayer.seeking)
        XCTAssertEqual(completionResult, false)
        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testQueuedSeekFromReplacedSessionCompletesFalse() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = try makeTemporaryTinyVideoFile()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        waitUntilReadyToPlay(try XCTUnwrap(avPlayer.avPlayerItem))
        let oldToken = try XCTUnwrap(avPlayer.session.currentToken)
        let completion = expectation(description: "stale seek rejected")
        var result: Bool?

        avPlayer.seek(to: 0) {
            result = $0
            completion.fulfill()
        }
        avPlayer.replaceEmpty()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(result, false)
        XCTAssertFalse(avPlayer.seeking)
        XCTAssertNotEqual(avPlayer.session.currentToken, oldToken)
        XCTAssertEqual(avPlayer.session.diagnostics.phase, .active)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testProgressReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertEqual(avPlayer.progress, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testDurationReturnsZeroWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertEqual(avPlayer.duration, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPresentationSizeAndBitrateReturnFallbacksWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertEqual(avPlayer.presentationSize, .zero)
        XCTAssertEqual(avPlayer.bitrate, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReloadVolumeIgnoresMissingPlayerInstance() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.reloadVolume()

        XCTAssertNil(avPlayer.avPlayer)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReloadVolumeIgnoresReleasedAbstractPlayer() {
        var retainedPlayer: IRAVPlayer?
        autoreleasepool {
            let abstractPlayer = IRPlayerImp.player()
            let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
            activate(avPlayer, url: missingMediaURL())
            retainedPlayer = avPlayer
        }

        XCTAssertNil(retainedPlayer?.abstractPlayer)
        retainedPlayer?.reloadVolume()
        retainedPlayer?.presentationLoop.close()
    }

    func testReloadPlayableTimeClearsWhenItemIsMissingOrNotReady() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        avPlayer.playableTime = 5

        avPlayer.reloadPlayableTime()
        XCTAssertEqual(avPlayer.playableTime, 0)

        avPlayer.playableTime = 6
        activate(avPlayer, url: missingMediaURL())
        avPlayer.reloadPlayableTime()
        XCTAssertEqual(avPlayer.playableTime, 0)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPlaybackErrorInfoFallsBackWhenPlayerItemAndPlayerAreMissing() {
        let errorInfo = IRAVPlayerErrorPolicy.playbackErrorInfo(playerItem: nil, player: nil)

        XCTAssertEqual(errorInfo.error.domain, "AVPlayer playback error")
        XCTAssertEqual(errorInfo.error.code, -1)
    }

    func testPlaybackErrorInfoPrefersPlayerItemErrorAndCopiesLogPayloads() throws {
        let itemError = NSError(domain: "item", code: 11)
        let playerError = NSError(domain: "player", code: 22)
        let date = Date(timeIntervalSince1970: 77)
        let logData = Data("log".utf8)

        let errorInfo = IRAVPlayerErrorPolicy.errorInfo(
            playerItemError: itemError,
            playerError: playerError,
            extendedLogData: logData,
            extendedLogDataStringEncoding: String.Encoding.utf16.rawValue,
            errorEvents: [
                IRAVPlayerErrorPolicy.ErrorLogEventSnapshot(
                    date: date,
                    URI: "https://example.com/error.ts",
                    serverAddress: "203.0.113.8",
                    playbackSessionID: "session-77",
                    errorStatusCode: 404,
                    errorDomain: "cdn",
                    errorComment: "missing"
                )
            ]
        )

        XCTAssertEqual(errorInfo.error.domain, "item")
        XCTAssertEqual(errorInfo.error.code, 11)
        XCTAssertEqual(errorInfo.extendedLogData, logData)
        XCTAssertEqual(errorInfo.extendedLogDataStringEncoding, String.Encoding.utf16.rawValue)

        XCTAssertEqual(errorInfo.errorEvents?.count, 1)
        let event = try XCTUnwrap(errorInfo.errorEvents?.first)
        XCTAssertEqual(event.date, date)
        XCTAssertEqual(event.URI, "https://example.com/error.ts")
        XCTAssertEqual(event.serverAddress, "203.0.113.8")
        XCTAssertEqual(event.playbackSessionID, "session-77")
        XCTAssertEqual(event.errorStatusCode, 404)
        XCTAssertEqual(event.errorDomain, "cdn")
        XCTAssertEqual(event.errorComment, "missing")
    }

    func testPlaybackErrorInfoUsesPlayerErrorWhenItemErrorIsMissing() {
        let playerError = NSError(domain: "player", code: 22)

        let errorInfo = IRAVPlayerErrorPolicy.errorInfo(
            playerItemError: nil,
            playerError: playerError,
            extendedLogData: Data("ignored".utf8),
            extendedLogDataStringEncoding: String.Encoding.utf16.rawValue,
            errorEvents: [
                IRAVPlayerErrorPolicy.ErrorLogEventSnapshot(
                    date: Date(timeIntervalSince1970: 1),
                    URI: "ignored",
                    serverAddress: "ignored",
                    playbackSessionID: "ignored",
                    errorStatusCode: 500,
                    errorDomain: "ignored",
                    errorComment: "ignored"
                )
            ]
        )

        XCTAssertEqual(errorInfo.error.domain, "player")
        XCTAssertEqual(errorInfo.error.code, 22)
        XCTAssertNil(errorInfo.extendedLogData)
        XCTAssertNil(errorInfo.errorEvents)
    }

    func testPlaybackErrorEventBuilderCopiesSnapshotFields() {
        let date = Date(timeIntervalSince1970: 42)

        let event = IRAVPlayerErrorPolicy.errorEvent(
            date: date,
            URI: "https://example.com/segment.ts",
            serverAddress: "198.51.100.10",
            playbackSessionID: "session-1",
            errorStatusCode: 503,
            errorDomain: "cdn",
            errorComment: "unavailable"
        )

        XCTAssertEqual(event.date, date)
        XCTAssertEqual(event.URI, "https://example.com/segment.ts")
        XCTAssertEqual(event.serverAddress, "198.51.100.10")
        XCTAssertEqual(event.playbackSessionID, "session-1")
        XCTAssertEqual(event.errorStatusCode, 503)
        XCTAssertEqual(event.errorDomain, "cdn")
        XCTAssertEqual(event.errorComment, "unavailable")
    }

    func testPlaybackErrorExtendedLogDataAppliesOnlyNonEmptyPayloads() {
        let errorInfo = IRError()

        IRAVPlayerErrorPolicy.applyExtendedLogData(
            Data(),
            stringEncoding: String.Encoding.utf16.rawValue,
            to: errorInfo
        )
        XCTAssertNil(errorInfo.extendedLogData)
        XCTAssertEqual(errorInfo.extendedLogDataStringEncoding, String.Encoding.utf8.rawValue)

        let logData = Data([1, 2, 3])
        IRAVPlayerErrorPolicy.applyExtendedLogData(
            logData,
            stringEncoding: String.Encoding.utf16.rawValue,
            to: errorInfo
        )

        XCTAssertEqual(errorInfo.extendedLogData, logData)
        XCTAssertEqual(errorInfo.extendedLogDataStringEncoding, String.Encoding.utf16.rawValue)
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
            IRAVPlayerSession.assetLoadDecision(keyStatuses: [.loaded, .failed], trackStatus: .loaded),
            .fail
        )
    }

    func testAVAssetLoadDecisionSetsUpOutputWhenTracksAreLoaded() {
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: .loaded),
            .setupOutput
        )
    }

    func testAVAssetLoadDecisionIgnoresIncompleteTrackStatus() {
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: .loading),
            .ignore
        )
        XCTAssertEqual(
            IRAVPlayerSession.assetLoadDecision(keyStatuses: [.loaded, .loaded], trackStatus: nil),
            .ignore
        )
    }

    func testResourceLoaderRedirectRequestAppliesHeadersToHTTPSRequests() throws {
        var request = URLRequest(url: URL(string: "https://example.com/video.m3u8")!)
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)

        let redirectRequest = try XCTUnwrap(IRAVPlayerSession.resourceLoaderRedirectRequest(
            for: request,
            headers: [
                "Authorization": "Bearer token",
                "X-Playback-Session": "abc"
            ]
        ))

        XCTAssertEqual(redirectRequest.url, request.url)
        XCTAssertEqual(redirectRequest.httpMethod, "POST")
        XCTAssertEqual(redirectRequest.httpBody, request.httpBody)
        XCTAssertEqual(redirectRequest.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(redirectRequest.value(forHTTPHeaderField: "X-Playback-Session"), "abc")
    }

    func testResourceLoaderRedirectRequestRejectsMissingHeaders() {
        let request = URLRequest(url: URL(string: "https://example.com/video.m3u8")!)

        XCTAssertNil(IRAVPlayerSession.resourceLoaderRedirectRequest(for: request, headers: nil))
        XCTAssertNil(IRAVPlayerSession.resourceLoaderRedirectRequest(for: request, headers: [:]))
    }

    func testResourceLoaderRedirectRequestRejectsNonHTTPSURLs() {
        let request = URLRequest(url: URL(string: "http://example.com/video.m3u8")!)

        XCTAssertNil(IRAVPlayerSession.resourceLoaderRedirectRequest(
            for: request,
            headers: ["Authorization": "Bearer token"]
        ))
    }

    func testUnknownItemStatusBuffersWithoutDebugOutput() {
        let output = captureStandardOutput {
            XCTAssertEqual(
                IRAVPlayer.itemStatusDecision(
                    status: .unknown,
                    currentState: .none
                ),
                .buffer
            )
        }

        XCTAssertEqual(output, "")
    }

    func testLoadedTimeRangesReloadClearsPlayableTimeWithoutRange() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.playableTime = 5
        activate(avPlayer, url: missingMediaURL())
        avPlayer.reloadPlayableTime()

        XCTAssertEqual(avPlayer.playableTime, 0)
        XCTAssertFalse(avPlayer.needPlay)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testFinishedNotificationMarksPlayerFinished() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        activate(avPlayer, url: missingMediaURL())
        let item = try? XCTUnwrap(avPlayer.avPlayerItem)

        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        waitForMainQueue()

        XCTAssertEqual(avPlayer.state, .finished)
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

    func testAVAssetPrepareFailureMarksPlayerFailedAndPostsError() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let error = NSError(domain: "IRAVPlayerTests.assetLoad", code: 7)
        let expectation = observeNotification(
            name: IRPlayerErrorNotificationName,
            object: abstractPlayer
        ) { notification in
            let playerError = IRModel.error(fromUserInfo: try XCTUnwrap(notification.userInfo))
            XCTAssertEqual(playerError.error.domain, error.domain)
            XCTAssertEqual(playerError.error.code, error.code)
        }

        avPlayer.avAssetPrepareFailed(error: error)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(avPlayer.state, .failed)
        XCTAssertEqual(abstractPlayer.error?.error.domain, error.domain)
        XCTAssertEqual(abstractPlayer.error?.error.code, error.code)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testAVAssetPrepareFailureDeactivatesPresentationLoop() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let token = try XCTUnwrap(
            activate(
                avPlayer,
                url: missingMediaURL(
                    named: "failed-vr-presentation.mp4"
                )
            )
        )
        XCTAssertNotNil(
            avPlayer.presentationLoop.activate(
                sessionToken: token
            )
        )

        avPlayer.avAssetPrepareFailed(
            error: NSError(
                domain: "IRAVPlayerTests.assetLoad",
                code: 8
            )
        )

        XCTAssertEqual(
            avPlayer.presentationLoop.diagnostics.phase,
            .idle
        )
        XCTAssertEqual(avPlayer.state, .failed)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testFailureWithoutAbstractPlayerStillMarksPlayerFailed() throws {
        var retainedPlayer: IRAVPlayer?
        autoreleasepool {
            let abstractPlayer = IRPlayerImp.player()
            retainedPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        }
        let avPlayer = try XCTUnwrap(retainedPlayer)

        avPlayer.avAssetPrepareFailed(error: nil)

        XCTAssertEqual(avPlayer.state, .failed)
        XCTAssertNil(avPlayer.abstractPlayer)
        avPlayer.presentationLoop.close()
    }

    func testFailedStatusObservationPostsPlaybackError() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = missingMediaURL(
            named: "missing-status-\(UUID().uuidString).mp4"
        )

        let expectation = observeNotification(
            name: IRPlayerErrorNotificationName,
            object: abstractPlayer
        ) { notification in
            let playerError = IRModel.error(fromUserInfo: try XCTUnwrap(notification.userInfo))
            XCTAssertNotEqual(playerError.error.domain, "")
        }

        activate(avPlayer, url: url)
        avPlayer.avPlayer?.play()
        waitUntilFailed(try XCTUnwrap(avPlayer.avPlayerItem))

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(avPlayer.state, .failed)
        XCTAssertEqual(avPlayer.readyToPlayTime, 0)
        XCTAssertNotNil(abstractPlayer.error)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPixelBufferAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertNil(avPlayer.pixelBufferAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }

    func testPixelBufferAtCurrentTimeReturnsNilWithoutVideoOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        activate(avPlayer, url: missingMediaURL())

        XCTAssertNil(avPlayer.pixelBufferAtCurrentTime())
        XCTAssertNil(avPlayer.avOutput)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testTrySetupOutputIgnoresMissingSessionWithoutDebugOutput() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        let output = captureStandardOutput {
            avPlayer.trySetupOutput()
        }

        XCTAssertNil(avPlayer.avOutput)
        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    func testTrySetupOutputIgnoresMissingOrNotReadyPlayerItem() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.readyToPlayTime = Date().timeIntervalSince1970 - 1
        avPlayer.trySetupOutput()
        XCTAssertNil(avPlayer.avOutput)

        activate(avPlayer, url: missingMediaURL())
        avPlayer.trySetupOutput()
        XCTAssertNil(avPlayer.avOutput)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSessionCreatesOutputAndResetRemovesIt() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = try makeTemporaryTinyVideoFile()

        let token = try XCTUnwrap(activate(avPlayer, url: url))
        XCTAssertTrue(
            avPlayer.session.rebuildVideoOutput(for: token)
        )

        let item = try XCTUnwrap(avPlayer.avPlayerItem)
        let output = try XCTUnwrap(avPlayer.avOutput)
        XCTAssertTrue(item.outputs.contains { $0 === output })

        avPlayer.replaceEmpty()

        XCTAssertNil(avPlayer.avPlayerItem)
        XCTAssertFalse(item.outputs.contains { $0 === output })
        withExtendedLifetime(abstractPlayer) {}
    }

    func testTrySetupOutputRebuildsOutputForReadyItemAfterWarmup() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = try makeTemporaryTinyVideoFile()

        let token = try XCTUnwrap(
            activate(
                avPlayer,
                url: url,
                automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
            )
        )
        let item = try XCTUnwrap(avPlayer.avPlayerItem)
        waitUntilReadyToPlay(item)
        XCTAssertTrue(
            avPlayer.session.rebuildVideoOutput(for: token)
        )
        let originalOutput = try XCTUnwrap(avPlayer.avOutput)

        avPlayer.readyToPlayTime = Date().timeIntervalSince1970 - 1
        avPlayer.trySetupOutput()

        let rebuiltOutput = try XCTUnwrap(avPlayer.avOutput)
        XCTAssertFalse(rebuiltOutput === originalOutput)
        XCTAssertTrue(item.outputs.contains { $0 === rebuiltOutput })
        XCTAssertFalse(item.outputs.contains { $0 === originalOutput })
        withExtendedLifetime(abstractPlayer) {}
    }

    func testReplaceVideoWithNormalURLConfiguresAVPlayerLayerRenderer() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.AVPlayerDecoder()
        let displayView = try XCTUnwrap(player.view as? IRGLView)

        player.replaceVideoWithURL(contentURL: missingMediaURL() as NSURL, videoType: .normal)

        XCTAssertEqual(displayView.rendererType, .AVPlayerLayer)
        XCTAssertTrue(
            displayView.attachedAVPlayer ===
                loadedAVPlayer(from: player)?.avPlayer
        )
        XCTAssertEqual(player.state, .none)
        XCTAssertEqual(player.presentationSize, .zero)
        withExtendedLifetime(player) {}
    }

    func testGeneratedNormalVideoConfiguresTracksAndPlaybackControls() throws {
        let url = try makeTemporaryTinyVideoFile()
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.AVPlayerDecoder()
        let displayView = try XCTUnwrap(player.view as? IRGLView)

        player.replaceVideoWithURL(contentURL: url as NSURL, videoType: .normal)

        let avPlayer = try XCTUnwrap(loadedAVPlayer(from: player))
        let item = try XCTUnwrap(avPlayer.avPlayerItem)
        waitUntilReadyToPlay(item)
        waitForMainQueue()

        XCTAssertEqual(displayView.rendererType, .AVPlayerLayer)
        XCTAssertTrue(displayView.attachedAVPlayer === avPlayer.avPlayer)
        XCTAssertEqual(avPlayer.state, .readyToPlay)
        XCTAssertNil(avPlayer.avOutput)
        XCTAssertEqual(
            avPlayer.presentationLoop.diagnostics.phase,
            .idle
        )
        XCTAssertTrue(avPlayer.videoEnable)
        XCTAssertFalse(avPlayer.audioEnable)
        XCTAssertEqual(avPlayer.videoTracks.count, 1)
        XCTAssertGreaterThan(avPlayer.videoTracks.first?.index ?? 0, 0)
        XCTAssertTrue(avPlayer.audioTracks.isEmpty)
        XCTAssertEqual(avPlayer.presentationSize, CGSize(width: 16, height: 16))
        XCTAssertGreaterThan(avPlayer.duration, 0)
        XCTAssertGreaterThanOrEqual(avPlayer.bitrate, 0)

        avPlayer.play()
        XCTAssertEqual(avPlayer.state, .playing)

        avPlayer.setPlayIfNeeded()
        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)

        avPlayer.playIfNeeded()
        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)

        let seekFinished = expectation(description: "seek finished")
        avPlayer.seek(to: 0) { finished in
            XCTAssertTrue(finished)
            seekFinished.fulfill()
        }
        wait(for: [seekFinished], timeout: 2)
        XCTAssertFalse(avPlayer.seeking)
        XCTAssertEqual(avPlayer.state, .playing)

        XCTAssertNotNil(avPlayer.snapshotAtCurrentTime())

        avPlayer.pause()
        XCTAssertEqual(avPlayer.state, .suspend)
        avPlayer.replaceEmpty()
        XCTAssertNil(displayView.attachedAVPlayer)
        XCTAssertEqual(
            avPlayer.presentationLoop.diagnostics.phase,
            .idle
        )
        withExtendedLifetime(player) {}
    }

    func testGeneratedVRVideoConfiguresPixelBufferRendererAndCompletesAsyncAssetLoad() throws {
        let url = try makeTemporaryTinyVideoFile()
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.AVPlayerDecoder()
        let displayView = try XCTUnwrap(player.view as? IRGLView)

        player.replaceVideoWithURL(contentURL: url as NSURL, videoType: .vr)

        let avPlayer = try XCTUnwrap(loadedAVPlayer(from: player))
        let item = try XCTUnwrap(avPlayer.avPlayerItem)
        let asset = try XCTUnwrap(avPlayer.avAsset)
        waitUntilReadyToPlay(item)
        waitUntilAssetKeysResolved(asset)
        waitForMainQueue(after: 0.2)

        XCTAssertEqual(displayView.rendererType, .AVPlayerPixelBufferVR)
        XCTAssertNil(displayView.attachedAVPlayer)
        XCTAssertNotNil(avPlayer.avOutput)
        XCTAssertEqual(
            avPlayer.presentationLoop.diagnostics.phase,
            .active
        )
        if let output = avPlayer.avOutput {
            XCTAssertTrue(item.outputs.contains { $0 === output })
        }
        avPlayer.replaceEmpty()
        XCTAssertEqual(
            avPlayer.presentationLoop.diagnostics.phase,
            .idle
        )
        XCTAssertNil(avPlayer.avOutput)
        withExtendedLifetime(player) {}
    }

    func testBackendDeinitClosesInjectedPresentationLoop() {
        let abstractPlayer = IRPlayerImp.player()
        let loop = IRAVPlayerPresentationLoop.system()
        weak var weakAVPlayer: IRAVPlayer?

        autoreleasepool {
            var avPlayer: IRAVPlayer? = IRAVPlayer(
                abstractPlayer: abstractPlayer,
                presentationLoop: loop
            )
            weakAVPlayer = avPlayer
            XCTAssertEqual(
                loop.diagnostics.phase,
                .idle
            )
            avPlayer = nil
        }

        XCTAssertNil(weakAVPlayer)
        XCTAssertEqual(
            loop.diagnostics.phase,
            .closed
        )
        XCTAssertEqual(loop.diagnostics.closeCount, 1)
    }

    func testReplaceVideoWithCustomAndFisheyeURLsLeaveRendererUnconfigured() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        player.decoder = IRPlayerDecoder.AVPlayerDecoder()
        let displayView = try XCTUnwrap(player.view as? IRGLView)

        player.replaceVideoWithURL(contentURL: missingMediaURL() as NSURL, videoType: .custom)

        XCTAssertEqual(displayView.rendererType, .empty)
        XCTAssertEqual(player.state, .none)
        XCTAssertNil(loadedAVPlayer(from: player)?.avPlayerItem)

        player.replaceVideoWithURL(contentURL: missingMediaURL(named: "missing-fisheye.mp4") as NSURL, videoType: .fisheye)

        XCTAssertEqual(displayView.rendererType, .empty)
        XCTAssertEqual(player.state, .none)
        withExtendedLifetime(player) {}
    }

    func testSetupTrackInfoAndAudioTrackSelectionIgnoreMissingAssetGroups() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        avPlayer.setupTrackInfo()
        avPlayer.selectAudioTrack(index: 7)

        XCTAssertFalse(avPlayer.videoEnable)
        XCTAssertFalse(avPlayer.audioEnable)
        XCTAssertTrue(avPlayer.videoTracks.isEmpty)
        XCTAssertTrue(avPlayer.audioTracks.isEmpty)
        XCTAssertNil(avPlayer.audioTrack)
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSnapshotAtCurrentTimeReturnsNilWhenPlayerItemIsMissing() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)

        XCTAssertNil(avPlayer.snapshotAtCurrentTime())
        withExtendedLifetime(abstractPlayer) {}
    }

    func testSnapshotAtCurrentTimeReturnsNilWithoutDebugOutputWhenImageGenerationFails() {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(abstractPlayer: abstractPlayer)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing.mp4")

        activate(avPlayer, url: url)
        let output = captureStandardOutput {
            XCTAssertNil(avPlayer.snapshotAtCurrentTime())
        }

        XCTAssertEqual(output, "")
        withExtendedLifetime(abstractPlayer) {}
    }

    @discardableResult
    private func activate(
        _ player: IRAVPlayer,
        url: URL,
        automaticallyLoadedAssetKeys: [String]? = nil
    ) -> IRAVPlayerSession.Token? {
        player.activateSession(
            asset: AVURLAsset(url: url),
            automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys
        )
    }

    private func missingMediaURL(named name: String = "missing.mp4") -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    private func makeTemporaryTinyVideoFile() throws -> URL {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func waitUntilReadyToPlay(_ item: AVPlayerItem) {
        let ready = expectation(description: "AVPlayerItem ready")
        var didFulfill = false
        var observation: NSKeyValueObservation?
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard !didFulfill else { return }
            switch item.status {
            case .readyToPlay:
                didFulfill = true
                ready.fulfill()
            case .failed:
                didFulfill = true
                XCTFail("AVPlayerItem failed: \(String(describing: item.error))")
                ready.fulfill()
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        wait(for: [ready], timeout: 10)
        observation?.invalidate()
    }

    private func waitUntilFailed(_ item: AVPlayerItem) {
        let failed = expectation(description: "AVPlayerItem failed")
        var didFulfill = false
        var observation: NSKeyValueObservation?
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            guard !didFulfill else { return }
            switch item.status {
            case .failed:
                didFulfill = true
                failed.fulfill()
            case .readyToPlay:
                didFulfill = true
                XCTFail("AVPlayerItem unexpectedly became ready.")
                failed.fulfill()
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        wait(for: [failed], timeout: 5)
        observation?.invalidate()
    }

    private func waitUntilAssetKeysResolved(_ asset: AVURLAsset) {
        let loaded = expectation(description: "AVURLAsset keys resolved")
        asset.loadValuesAsynchronously(forKeys: IRAVPlayer.AVAssetLoadKeys) {
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
    }

    private func waitForMainQueue(after delay: TimeInterval = 0) {
        let settled = expectation(description: "main queue settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: delay + 1)
    }

    private func observeNotification(
        name: String,
        object: Any?,
        verify: @escaping (Notification) throws -> Void
    ) -> XCTestExpectation {
        let expectation = expectation(description: "\(name) posted")
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(name),
            object: object,
            queue: .main
        ) { notification in
            do {
                try verify(notification)
            } catch {
                XCTFail("Notification verification failed: \(error)")
            }
            expectation.fulfill()
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(observer)
        }
        return expectation
    }
}

private final class AVPlaybackBackendHostSpy: IRPlaybackBackendHost {
    var contentURL: NSURL?
    var contentHeaders: [String: String]?
    var videoType: IRVideoType = .normal
    var videoInput: IRFFVideoInput?
    var decoder = IRPlayerDecoder.AVPlayerDecoder()
    var displayView: IRGLView?
    var manager: IRAudioManager?
    var error: IRError?
    var volume: CGFloat = 1
    var playableBufferInterval: TimeInterval = 2
    var isLiveStream = false

    private(set) var stateChanges = 0
    private(set) var progressUpdates = 0
    private(set) var playableUpdates = 0
    private(set) var failures = 0

    init(contentURL: NSURL?) {
        self.contentURL = contentURL
    }

    func playbackBackendDidChangeState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        stateChanges += 1
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        progressUpdates += 1
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        playableUpdates += 1
    }

    func playbackBackendDidFail(_ error: IRError) {
        failures += 1
    }
}
