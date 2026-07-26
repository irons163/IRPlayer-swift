import AVFoundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

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

    func testSeekClampsToDurationFromTheCapturedItem() throws {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let recorder = AVSeekExecutorRecorder()
        let avPlayer = IRAVPlayer(
            abstractPlayer: host,
            itemSeekExecutor: recorder.execute
        )
        let url = try makeTemporaryTinyVideoFile()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        let item = try XCTUnwrap(avPlayer.avPlayerItem)
        waitUntilReadyToPlay(item)
        let duration = avPlayer.duration
        XCTAssertGreaterThan(duration, 0)

        avPlayer.seek(to: duration + 100)
        waitForMainQueue()

        XCTAssertEqual(recorder.invocationCount, 1)
        XCTAssertTrue(recorder.lastItem === item)
        let recordedTime = try XCTUnwrap(recorder.lastTime)
        XCTAssertEqual(
            CMTimeGetSeconds(recordedTime),
            duration,
            accuracy: 0.001
        )
        avPlayer.cancelPendingSeek()
    }

    func testQueuedClampedSeekCannotReachReplacementItem() throws {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let recorder = AVSeekExecutorRecorder()
        let avPlayer = IRAVPlayer(
            abstractPlayer: host,
            itemSeekExecutor: recorder.execute
        )
        let url = try makeTemporaryTinyVideoFile()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        waitUntilReadyToPlay(try XCTUnwrap(avPlayer.avPlayerItem))
        let completed = expectation(
            description: "stale clamped seek rejected"
        )
        var result: Bool?

        avPlayer.seek(to: avPlayer.duration + 100) {
            result = $0
            completed.fulfill()
        }
        avPlayer.replaceEmpty()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(result, false)
        XCTAssertEqual(recorder.invocationCount, 0)
        XCTAssertFalse(avPlayer.seeking)
    }

    func testPlayBeforeReadyPreservesAutoplayIntent() throws {
        let host = AVPlaybackBackendHostSpy(
            contentURL: missingMediaURL() as NSURL
        )
        let avPlayer = IRAVPlayer(abstractPlayer: host)
        activate(avPlayer, url: missingMediaURL())

        avPlayer.play()

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)

        avPlayer.handleItemStatus(.readyToPlay)

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
    }

    func testDisplacedSeekReentrancyDoesNotSeekStaleItem() throws {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let recorder = AVSeekExecutorRecorder()
        let avPlayer = IRAVPlayer(
            abstractPlayer: host,
            itemSeekExecutor: recorder.execute
        )
        let url = try makeTemporaryTinyVideoFile()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        waitUntilReadyToPlay(try XCTUnwrap(avPlayer.avPlayerItem))
        var firstResult: Bool?
        var secondResult: Bool?

        avPlayer.seek(to: 0) { result in
            firstResult = result
            if !result {
                avPlayer.replaceEmpty()
            }
        }
        waitForMainQueue()
        XCTAssertEqual(recorder.invocationCount, 1)

        avPlayer.seek(to: 0) { secondResult = $0 }
        waitForMainQueue()

        XCTAssertEqual(firstResult, false)
        XCTAssertEqual(secondResult, false)
        XCTAssertEqual(recorder.invocationCount, 1)
        XCTAssertFalse(avPlayer.seeking)
    }

    func testSeekCompletionRevalidatesAfterPlayingCallback() throws {
        let abstractPlayer = IRPlayerImp.player()
        let avPlayer = IRAVPlayer(
            abstractPlayer: abstractPlayer,
            itemSeekExecutor: { _, _, completion in
                completion(true)
            }
        )
        let url = try makeTemporaryTinyVideoFile()
        activate(
            avPlayer,
            url: url,
            automaticallyLoadedAssetKeys: IRAVPlayer.AVAssetLoadKeys
        )
        waitUntilReadyToPlay(try XCTUnwrap(avPlayer.avPlayerItem))
        avPlayer.state = .playing
        var didReset = false
        let observation = abstractPlayer.observeEvents { event in
            guard !didReset,
                  case let .stateChanged(_, current) = event,
                  current == .playing else {
                return
            }
            didReset = true
            avPlayer.replaceEmpty()
        }
        let completed = expectation(description: "seek completion")
        var result: Bool?

        avPlayer.seek(to: 0) {
            result = $0
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertTrue(didReset)
        XCTAssertEqual(result, false)
        XCTAssertFalse(avPlayer.seeking)
        withExtendedLifetime(observation) {}
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

    func testPlayableTimeSupportsConcurrentReadsAndWrites() {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let avPlayer = IRAVPlayer(abstractPlayer: host)
        let group = DispatchGroup()
        let invalidValue = AVConcurrentBoolBox()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for index in 0..<5_000 {
                avPlayer.playableTime = TimeInterval(index % 100)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<5_000 {
                let value = avPlayer.playableTime
                if !value.isFinite || value < 0 || value >= 100 {
                    invalidValue.value = true
                }
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertFalse(invalidValue.value)
    }

    func testSnapshotPublishesSynchronizedPlayableTime() {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let avPlayer = IRAVPlayer(abstractPlayer: host)
        activate(avPlayer, url: missingMediaURL())
        avPlayer.playableTime = 7

        XCTAssertEqual(avPlayer.snapshot.playableTime, 7)
    }

    func testPlayableTimeNormalizesInvalidAndNegativeValues() {
        let host = AVPlaybackBackendHostSpy(contentURL: nil)
        let avPlayer = IRAVPlayer(abstractPlayer: host)

        for value in [
            TimeInterval.nan,
            .infinity,
            -.infinity,
            -1,
            .greatestFiniteMagnitude
        ] {
            avPlayer.playableTime = value
            XCTAssertEqual(avPlayer.playableTime, 0)
            XCTAssertEqual(avPlayer.snapshot.playableTime, 0)
        }
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

    func testUnknownDurationLoadedRangeRecoversBufferedPlayback() {
        let host = AVPlaybackBackendHostSpy(
            contentURL: missingMediaURL() as NSURL
        )
        let avPlayer = IRAVPlayer(abstractPlayer: host)
        activate(avPlayer, url: missingMediaURL())
        avPlayer.state = .playing
        avPlayer.setPlayIfNeeded()

        XCTAssertEqual(avPlayer.state, .buffering)
        XCTAssertTrue(avPlayer.needPlay)

        avPlayer.reevaluatePlaybackAfterLoadedTimeRange(
            playableTime: IRAVPlayer.playableEndTime(
                start: 0,
                duration: 5,
                totalDuration: 0
            ),
            progress: 0,
            totalDuration: 0,
            playableBufferInterval: host.playableBufferInterval
        )

        XCTAssertEqual(avPlayer.state, .playing)
        XCTAssertFalse(avPlayer.needPlay)
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

    func testAdvancedAutomaticSourcesResolveToFFmpeg() {
        let decoder = IRPlayerDecoder.AVPlayerDecoder()
        let url = missingMediaURL()

        XCTAssertEqual(
            IRMediaSource(
                url: url,
                videoType: .custom
            ).decoderType(using: decoder),
            .ffmpeg
        )
        XCTAssertEqual(
            IRMediaSource(
                url: url,
                videoType: .fisheye
            ).decoderType(using: decoder),
            .ffmpeg
        )
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

private final class AVSeekExecutorRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedInvocationCount = 0
    private var storedLastItem: AVPlayerItem?
    private var storedLastTime: CMTime?

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInvocationCount
    }

    var lastItem: AVPlayerItem? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastItem
    }

    var lastTime: CMTime? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastTime
    }

    func execute(
        item: AVPlayerItem,
        time: CMTime,
        completion: @escaping (Bool) -> Void
    ) {
        lock.lock()
        storedInvocationCount += 1
        storedLastItem = item
        storedLastTime = time
        lock.unlock()
    }
}

private final class AVConcurrentBoolBox:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
