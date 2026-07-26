import CoreGraphics
import AVFoundation
import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFPlayerExecutorOwnerTests: XCTestCase {
    func testSyncIsReentrantWithoutDeadlock() {
        let executor = IRFFPlayerExecutor(
            label: "IRFFPlayerExecutorOwnerTests.reentrant"
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
        let executor = IRFFPlayerExecutor(
            label: "IRFFPlayerExecutorOwnerTests.serial"
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
        let executor = IRFFPlayerExecutor(
            label: "IRFFPlayerExecutorOwnerTests.async"
        )
        let completed = expectation(description: "async operations")
        let values = FFPlayerIntRecorder()

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

final class IRFFPlayerStateMachineOwnerTests: XCTestCase {
    func testMutableTransitionsOwnStateAndPlayIntent() {
        var machine = IRFFPlayerStateMachine()

        let playDecision = machine.beginPlay()
        XCTAssertTrue(machine.playRequested)
        XCTAssertEqual(playDecision.nextState, .buffering)
        XCTAssertFalse(playDecision.shouldSeekToStart)
        XCTAssertEqual(
            machine.transition(to: playDecision.nextState),
            .init(previous: .none, current: .buffering)
        )

        XCTAssertEqual(
            machine.applyBuffering(false),
            .init(previous: .buffering, current: .playing)
        )
        XCTAssertFalse(machine.hasPreparedOnce)

        XCTAssertEqual(
            machine.beginPause(),
            .init(previous: .playing, current: .suspend)
        )
        XCTAssertFalse(machine.playRequested)
    }

    func testPreparationTokenAdvancesOnlyForPausedUnbufferedPlayback() {
        var machine = IRFFPlayerStateMachine()
        _ = machine.transition(to: .buffering)

        XCTAssertEqual(
            machine.applyBuffering(false),
            .init(previous: .buffering, current: .readyToPlay)
        )
        XCTAssertTrue(machine.hasPreparedOnce)

        _ = machine.transition(to: .buffering)
        XCTAssertEqual(
            machine.applyBuffering(false),
            .init(previous: .buffering, current: .suspend)
        )
        XCTAssertTrue(machine.hasPreparedOnce)
    }

    func testResetClearsAllOwnedPlaybackState() {
        var machine = IRFFPlayerStateMachine()
        _ = machine.beginPlay()
        _ = machine.transition(to: .playing)
        _ = machine.applyBuffering(false)

        XCTAssertEqual(
            machine.reset(),
            .init(previous: .playing, current: .none)
        )
        XCTAssertEqual(machine.state, .none)
        XCTAssertFalse(machine.playRequested)
        XCTAssertFalse(machine.hasPreparedOnce)
        XCTAssertNil(machine.reset())
    }
}

final class IRFFPlayerDecoderSessionOwnerTests: XCTestCase {
    func testActivationPublishesCompleteGenerationBeforeOpen() throws {
        let decoder = ControlledFFPlayerDecoder()
        let source = IRFFVideoInput()
        let videoOutput = FFPlayerVideoOutputProbe()
        let audioOutput = FFPlayerAudioOutputProbe()
        let recorder = FFPlayerEventRecorder()
        let contentHeaders = [
            "Authorization":
                "Bearer value",
            "X-Playback": "primary"
        ]
        var session: IRFFPlayerDecoderSession!
        var factoryCallCount = 0

        session = IRFFPlayerDecoderSession {
            url,
            format,
            headers,
            video,
            audio in
            factoryCallCount += 1
            XCTAssertEqual(url.path, "/tmp/runtime-owner.mp4")
            XCTAssertEqual(format, .mpeg4)
            XCTAssertEqual(
                headers,
                contentHeaders
            )
            XCTAssertTrue(video === videoOutput)
            XCTAssertTrue(audio === audioOutput)
            decoder.videoOutput = video
            decoder.audioOutput = audio
            return decoder
        }
        decoder.onOpen = {
            XCTAssertTrue(session.currentDecoder === decoder)
            XCTAssertNotNil(decoder.delegate)
            XCTAssertTrue(decoder.source === source)
            XCTAssertTrue(decoder.hardwareDecoderEnable)
            XCTAssertTrue(decoder.isLiveStream)
            XCTAssertEqual(decoder.minBufferedDuration, 0.2)
            decoder.delegate?.decoderWillOpenInputStream(decoder)
        }

        let token = session.activate(
            configuration: makeFFPlayerSessionConfiguration(
                contentHeaders:
                    contentHeaders,
                source: source,
                videoOutput: videoOutput,
                audioOutput: audioOutput,
                hardwareDecoderEnabled: true,
                isLiveStream: true,
                minimumBufferedDuration: 0.2
            ),
            eventHandler: recorder.record
        )

        XCTAssertNotNil(token)
        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(decoder.openCount, 1)
        XCTAssertEqual(recorder.events, ["willOpenInput"])
        XCTAssertEqual(session.diagnostics.phase, .active)
        XCTAssertEqual(session.diagnostics.acceptedEventCount, 1)
        XCTAssertEqual(decoder.collaboratorDiagnostics.phase, .active)
        XCTAssertEqual(decoder.collaboratorDiagnostics.generation, 2)
        XCTAssertEqual(decoder.collaboratorDiagnostics.installCount, 2)
        XCTAssertTrue(decoder.collaboratorDiagnostics.hasDelegate)
        XCTAssertTrue(decoder.collaboratorDiagnostics.hasSource)
        XCTAssertTrue(decoder.collaboratorDiagnostics.hasVideoOutput)
        XCTAssertTrue(decoder.collaboratorDiagnostics.hasAudioOutput)
    }

    func testAdoptionInstallsBridgeWhilePreservingEveryExistingBinding() {
        let decoder = ControlledFFPlayerDecoder()
        let source = IRFFVideoInput()
        let videoOutput = FFPlayerVideoOutputProbe()
        let audioOutput = FFPlayerAudioOutputProbe()
        decoder.source = source
        decoder.videoOutput = videoOutput
        decoder.audioOutput = audioOutput
        let session = IRFFPlayerDecoderSession()

        XCTAssertNotNil(
            session.adopt(decoder, eventHandler: { _ in })
        )

        XCTAssertNotNil(decoder.delegate)
        XCTAssertTrue(decoder.source === source)
        XCTAssertTrue(decoder.videoOutput === videoOutput)
        XCTAssertTrue(decoder.audioOutput === audioOutput)
        XCTAssertEqual(decoder.collaboratorDiagnostics.phase, .active)
        XCTAssertEqual(decoder.collaboratorDiagnostics.generation, 2)
        XCTAssertEqual(decoder.collaboratorDiagnostics.installCount, 2)
    }

    func testActivationRejectsDecoderWhoseCollaboratorsAreRevoked() {
        let decoder = ControlledFFPlayerDecoder()
        XCTAssertTrue(decoder.revokeCollaborators())
        let session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in
            decoder
        }

        XCTAssertNil(
            session.activate(
                configuration: makeFFPlayerSessionConfiguration(),
                eventHandler: { _ in }
            )
        )

        XCTAssertNil(session.currentDecoder)
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
        XCTAssertEqual(decoder.closeCount, 1)
        XCTAssertEqual(decoder.collaboratorDiagnostics.phase, .revoked)
        XCTAssertEqual(
            decoder.collaboratorDiagnostics.rejectedUpdateCount,
            1
        )
    }

    func testFactoryReentrantCloseCannotResurrectSession() {
        let decoder = ControlledFFPlayerDecoder()
        var session: IRFFPlayerDecoderSession!
        session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in
            XCTAssertTrue(session.close())
            return decoder
        }

        let token = session.activate(
            configuration: makeFFPlayerSessionConfiguration(),
            eventHandler: { _ in }
        )

        XCTAssertNil(token)
        XCTAssertNil(session.currentDecoder)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertEqual(session.diagnostics.closeCount, 1)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
        XCTAssertEqual(decoder.openCount, 0)
        XCTAssertEqual(decoder.closeCount, 1)
    }

    func testFactoryCannotOverwriteReentrantNewerGeneration() {
        let reentrant = ControlledFFPlayerDecoder()
        let displaced = ControlledFFPlayerDecoder()
        var session: IRFFPlayerDecoderSession!
        session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in
            XCTAssertNotNil(
                session.adopt(reentrant, eventHandler: { _ in })
            )
            return displaced
        }

        let token = session.activate(
            configuration: makeFFPlayerSessionConfiguration(),
            eventHandler: { _ in }
        )

        XCTAssertNil(token)
        XCTAssertTrue(session.currentDecoder === reentrant)
        XCTAssertEqual(session.diagnostics.phase, .active)
        XCTAssertEqual(session.diagnostics.adoptionCount, 1)
        XCTAssertEqual(session.diagnostics.activationCount, 0)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
        XCTAssertEqual(reentrant.closeCount, 0)
        XCTAssertEqual(displaced.closeCount, 1)
    }

    func testReplacementDetachesOldBridgeAndRejectsStaleCallbacks() throws {
        let session = IRFFPlayerDecoderSession()
        let first = ControlledFFPlayerDecoder()
        let second = ControlledFFPlayerDecoder()
        let firstRecorder = FFPlayerEventRecorder()
        let secondRecorder = FFPlayerEventRecorder()

        XCTAssertNotNil(
            session.adopt(first, eventHandler: firstRecorder.record)
        )
        let staleBridge = try XCTUnwrap(first.delegate)

        XCTAssertNotNil(
            session.adopt(second, eventHandler: secondRecorder.record)
        )
        XCTAssertNil(first.delegate)
        XCTAssertEqual(first.closeCount, 1)
        XCTAssertTrue(session.currentDecoder === second)
        XCTAssertEqual(first.collaboratorDiagnostics.phase, .revoked)
        XCTAssertEqual(first.collaboratorDiagnostics.revokeCount, 1)
        XCTAssertEqual(second.collaboratorDiagnostics.phase, .active)

        staleBridge.decoder(first, didChangeValueOfProgress: 99)
        second.delegate?.decoder(
            second,
            didChangeValueOfProgress: 7
        )

        XCTAssertEqual(firstRecorder.events, [])
        XCTAssertEqual(secondRecorder.events, ["progress:7.0"])
        XCTAssertEqual(session.diagnostics.rejectedEventCount, 1)
        XCTAssertEqual(session.diagnostics.acceptedEventCount, 1)
    }

    func testBridgeRejectsCallbackFromUnknownDecoder() throws {
        let session = IRFFPlayerDecoderSession()
        let owned = ControlledFFPlayerDecoder()
        let unknown = ControlledFFPlayerDecoder()
        let recorder = FFPlayerEventRecorder()
        XCTAssertNotNil(session.adopt(owned, eventHandler: recorder.record))
        let bridge = try XCTUnwrap(owned.delegate)

        bridge.decoder(unknown, didChangeValueOfProgress: 11)

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(session.diagnostics.rejectedEventCount, 1)
    }

    func testSuccessfulSeekCompletesExactlyOnce() {
        let session = IRFFPlayerDecoderSession()
        let decoder = ControlledFFPlayerDecoder()
        XCTAssertNotNil(session.adopt(decoder, eventHandler: { _ in }))
        let results = FFPlayerBoolRecorder()

        session.seek(to: 4, completion: results.append)
        XCTAssertEqual(session.diagnostics.pendingSeekCount, 1)

        decoder.finishSeek(at: 0, result: true)
        session.executor.sync {}
        decoder.finishSeek(at: 0, result: false)
        session.executor.sync {}

        XCTAssertEqual(results.values, [true])
        XCTAssertEqual(session.diagnostics.pendingSeekCount, 0)
    }

    func testResetCancelsPendingSeekExactlyOnceAndIgnoresLateCompletion() {
        let session = IRFFPlayerDecoderSession()
        let decoder = ControlledFFPlayerDecoder()
        XCTAssertNotNil(session.adopt(decoder, eventHandler: { _ in }))
        let results = FFPlayerBoolRecorder()

        session.seek(to: 5, completion: results.append)
        XCTAssertTrue(session.reset())
        decoder.finishSeek(at: 0, result: true)
        session.executor.sync {}

        XCTAssertEqual(results.values, [false])
        XCTAssertEqual(decoder.closeCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertEqual(session.diagnostics.pendingSeekCount, 0)
    }

    func testResetDetachesEveryDecoderLinkBeforeClose() {
        let source = IRFFVideoInput()
        let videoOutput = FFPlayerVideoOutputProbe()
        let audioOutput = FFPlayerAudioOutputProbe()
        let decoder = ControlledFFPlayerDecoder()
        let session = IRFFPlayerDecoderSession {
            _, _, _, video, audio in
            decoder.videoOutput = video
            decoder.audioOutput = audio
            return decoder
        }
        decoder.onClose = {
            XCTAssertNil(decoder.delegate)
            XCTAssertNil(decoder.source)
            XCTAssertNil(decoder.videoOutput)
            XCTAssertNil(decoder.audioOutput)
        }
        XCTAssertNotNil(
            session.activate(
                configuration: makeFFPlayerSessionConfiguration(
                    source: source,
                    videoOutput: videoOutput,
                    audioOutput: audioOutput
                ),
                eventHandler: { _ in }
            )
        )

        XCTAssertTrue(session.reset())

        XCTAssertEqual(decoder.closeCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .idle)
        XCTAssertEqual(decoder.collaboratorDiagnostics.phase, .revoked)
        XCTAssertEqual(decoder.collaboratorDiagnostics.revokeCount, 1)
        XCTAssertFalse(decoder.collaboratorDiagnostics.hasDelegate)
        XCTAssertFalse(decoder.collaboratorDiagnostics.hasSource)
        XCTAssertFalse(decoder.collaboratorDiagnostics.hasVideoOutput)
        XCTAssertFalse(decoder.collaboratorDiagnostics.hasAudioOutput)
    }

    func testSeekWithoutDecoderCompletesFalse() {
        let session = IRFFPlayerDecoderSession()
        var result: Bool?

        session.seek(to: 1) {
            result = $0
        }

        XCTAssertEqual(result, false)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
    }

    func testReentrantActivationResetPreventsDecoderOpen() {
        let decoder = ControlledFFPlayerDecoder()
        let session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in decoder
        }

        let token = session.activate(
            configuration: makeFFPlayerSessionConfiguration(),
            eventHandler: { _ in },
            didActivate: { _ in
                XCTAssertTrue(session.reset())
            }
        )

        XCTAssertNil(token)
        XCTAssertEqual(decoder.openCount, 0)
        XCTAssertEqual(decoder.closeCount, 1)
        XCTAssertEqual(session.diagnostics.phase, .idle)
    }

    func testReentrantReplacementDuringSeekCancellationWinsGeneration() {
        let original = ControlledFFPlayerDecoder()
        let reentrant = ControlledFFPlayerDecoder()
        let displaced = ControlledFFPlayerDecoder()
        var factoryCallCount = 0
        let session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in
            factoryCallCount += 1
            return displaced
        }
        XCTAssertNotNil(session.adopt(original, eventHandler: { _ in }))
        session.seek(to: 3) { finished in
            XCTAssertFalse(finished)
            XCTAssertNotNil(
                session.adopt(reentrant, eventHandler: { _ in })
            )
        }

        let token = session.activate(
            configuration: makeFFPlayerSessionConfiguration(),
            eventHandler: { _ in }
        )

        XCTAssertNil(token)
        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertEqual(reentrant.closeCount, 0)
        XCTAssertEqual(displaced.closeCount, 0)
        XCTAssertTrue(session.currentDecoder === reentrant)
        XCTAssertEqual(session.diagnostics.phase, .active)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
    }

    func testCloseBecomesTerminalBeforeCancelingSeekCompletions() {
        let original = ControlledFFPlayerDecoder()
        let rejected = ControlledFFPlayerDecoder()
        let session = IRFFPlayerDecoderSession()
        XCTAssertNotNil(session.adopt(original, eventHandler: { _ in }))
        var reentrantToken: IRFFPlayerDecoderSession.Token?
        session.seek(to: 3) { finished in
            XCTAssertFalse(finished)
            reentrantToken = session.adopt(
                rejected,
                eventHandler: { _ in }
            )
        }

        XCTAssertTrue(session.close())

        XCTAssertNil(reentrantToken)
        XCTAssertNil(session.currentDecoder)
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertEqual(rejected.closeCount, 0)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 1)
    }

    func testCloseIsTerminalAndIdempotent() {
        let original = ControlledFFPlayerDecoder()
        let rejected = ControlledFFPlayerDecoder()
        var factoryCallCount = 0
        let session = IRFFPlayerDecoderSession {
            _, _, _, _, _ in
            factoryCallCount += 1
            return rejected
        }
        XCTAssertNotNil(session.adopt(original, eventHandler: { _ in }))

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertNil(
            session.activate(
                configuration: makeFFPlayerSessionConfiguration(),
                eventHandler: { _ in }
            )
        )
        XCTAssertNil(session.adopt(rejected, eventHandler: { _ in }))
        XCTAssertFalse(session.reset())

        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertEqual(rejected.closeCount, 0)
        XCTAssertEqual(session.diagnostics.phase, .closed)
        XCTAssertEqual(session.diagnostics.closeCount, 1)
        XCTAssertEqual(session.diagnostics.rejectedCommandCount, 3)
    }
}

final class IRFFPlayerRuntimeOwnerTests: XCTestCase {
    func testPlaybackTimeNormalizationRejectsInvalidAndBoundsVOD() {
        for value in [
            TimeInterval.nan,
            .infinity,
            -.infinity,
            .greatestFiniteMagnitude
        ] {
            XCTAssertEqual(
                IRFFPlayerRuntime.normalizedPlaybackTime(
                    value,
                    duration: 10,
                    seekEnabled: true,
                    isLiveStream: false
                ),
                .init(
                    current: 0,
                    total: 10,
                    boundedDuration: 10
                )
            )
        }
        XCTAssertEqual(
            IRFFPlayerRuntime.normalizedPlaybackTime(
                -2,
                duration: 10,
                seekEnabled: true,
                isLiveStream: false
            ),
            .init(
                current: 0,
                total: 10,
                boundedDuration: 10
            )
        )
        XCTAssertEqual(
            IRFFPlayerRuntime.normalizedPlaybackTime(
                12,
                duration: 10,
                seekEnabled: true,
                isLiveStream: false
            ),
            .init(
                current: 10,
                total: 10,
                boundedDuration: 10
            )
        )
    }

    func testPlaybackTimeNormalizationPreservesIndefiniteValues() {
        for normalized in [
            IRFFPlayerRuntime.normalizedPlaybackTime(
                12,
                duration: 10,
                seekEnabled: true,
                isLiveStream: true
            ),
            IRFFPlayerRuntime.normalizedPlaybackTime(
                12,
                duration: 10,
                seekEnabled: false,
                isLiveStream: false
            ),
            IRFFPlayerRuntime.normalizedPlaybackTime(
                12,
                duration: 0,
                seekEnabled: true,
                isLiveStream: false
            )
        ] {
            XCTAssertEqual(
                normalized,
                .init(
                    current: 12,
                    total: 12,
                    boundedDuration: nil
                )
            )
        }
    }

    func testRuntimeStoresOnlyNormalizedPlaybackTimes() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(
            host: host,
            audioManager: nil
        )
        XCTAssertNotNil(
            runtime.adopt(
                ControlledFFPlayerDecoder(duration: 10)
            )
        )

        runtime.progress = .nan
        runtime.playableTime = .infinity
        XCTAssertEqual(runtime.snapshot.progress, 0)
        XCTAssertEqual(runtime.snapshot.playableTime, 0)

        runtime.progress = -2
        runtime.playableTime = -3
        XCTAssertEqual(runtime.snapshot.progress, 0)
        XCTAssertEqual(runtime.snapshot.playableTime, 0)

        runtime.progress = 12
        runtime.playableTime = 13
        XCTAssertEqual(runtime.snapshot.progress, 10)
        XCTAssertEqual(runtime.snapshot.playableTime, 10)
        XCTAssertEqual(host.lastProgress?.current, 10)
        XCTAssertEqual(host.lastProgress?.total, 10)
        XCTAssertEqual(host.lastPlayable?.current, 10)
        XCTAssertEqual(host.lastPlayable?.total, 10)
    }

    func testLiveRuntimePreservesTimesAndUsesCurrentAsTotal() {
        let host = FFPlayerRuntimeHostSpy()
        host.isLiveStream = true
        let runtime = IRFFPlayerRuntime(
            host: host,
            audioManager: nil
        )
        let decoder = ControlledFFPlayerDecoder(duration: 0)
        decoder.isLiveStream = true
        XCTAssertNotNil(runtime.adopt(decoder))

        runtime.progress = 7
        runtime.playableTime = 9

        XCTAssertEqual(runtime.snapshot.progress, 7)
        XCTAssertEqual(runtime.snapshot.playableTime, 9)
        XCTAssertEqual(host.lastProgress?.current, 7)
        XCTAssertEqual(host.lastProgress?.total, 7)
        XCTAssertEqual(host.lastPlayable?.current, 9)
        XCTAssertEqual(host.lastPlayable?.total, 9)
    }

    func testProgressDecisionPostsAtStartEndAndThrottleBoundary() {
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 0,
                oldProgress: 1,
                duration: 10,
                lastPostTime: 20,
                now: 20.1,
                seekEnabled: true
            ),
            .init(
                shouldPost: true,
                current: 0,
                total: 10,
                nextLastPostTime: 20
            )
        )
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 10,
                oldProgress: 9,
                duration: 10,
                lastPostTime: 20,
                now: 20.1,
                seekEnabled: true
            ),
            .init(
                shouldPost: true,
                current: 10,
                total: 10,
                nextLastPostTime: 20
            )
        )
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 5,
                oldProgress: 4,
                duration: 10,
                lastPostTime: 20,
                now: 20.5,
                seekEnabled: true
            ),
            .init(
                shouldPost: false,
                current: 5,
                total: 10,
                nextLastPostTime: 20
            )
        )
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 5,
                oldProgress: 4,
                duration: 10,
                lastPostTime: 20,
                now: 21,
                seekEnabled: true
            ),
            .init(
                shouldPost: true,
                current: 5,
                total: 10,
                nextLastPostTime: 21
            )
        )
    }

    func testProgressDecisionUsesProgressAsLiveDuration() {
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 5,
                oldProgress: 4,
                duration: 10,
                lastPostTime: 20,
                now: 21,
                seekEnabled: false
            ),
            .init(
                shouldPost: true,
                current: 5,
                total: 5,
                nextLastPostTime: 21
            )
        )
    }

    func testProgressDecisionRejectsUnchangedOrNonFiniteProgress() {
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: 4,
                oldProgress: 4,
                duration: 10,
                lastPostTime: 20,
                now: 21,
                seekEnabled: true
            ),
            .init(
                shouldPost: false,
                current: 4,
                total: 10,
                nextLastPostTime: 20
            )
        )
        XCTAssertEqual(
            IRFFPlayerRuntime.progressPostDecision(
                progress: .nan,
                oldProgress: 4,
                duration: 10,
                lastPostTime: 20,
                now: 21,
                seekEnabled: true
            ),
            .init(
                shouldPost: false,
                current: 0,
                total: 10,
                nextLastPostTime: 20
            )
        )
    }

    func testProgressDecisionRejectsInvalidDerivedElapsedTime() {
        let decision = IRFFPlayerRuntime.progressPostDecision(
            progress: 5,
            oldProgress: 4,
            duration: .nan,
            lastPostTime: -.greatestFiniteMagnitude,
            now: .greatestFiniteMagnitude,
            seekEnabled: true
        )

        XCTAssertEqual(
            decision,
            .init(
                shouldPost: false,
                current: 5,
                total: 0,
                nextLastPostTime: -.greatestFiniteMagnitude
            )
        )
    }

    func testReentrantReplaceRequestWinsFacadePresentationGeneration() {
        let host = FFPlayerRuntimeHostSpy()
        host.displayView = IRGLView(frame: .zero)
        host.contentURL = NSURL(fileURLWithPath: "/tmp/outer.mp4")
        let executor = IRFFPlayerExecutor()
        var factoryURLs: [URL] = []
        var createdDecoders: [ControlledFFPlayerDecoder] = []
        var player: IRFFPlayer!
        player = IRFFPlayer(
            abstractPlayer: host,
            dependencies: IRFFPlayer.Dependencies(
                executor: executor,
                decoderFactory: {
                    url,
                    _,
                    _,
                    video,
                    audio in
                    factoryURLs.append(url)
                    let decoder = ControlledFFPlayerDecoder(duration: 10)
                    decoder.videoOutput = video
                    decoder.audioOutput = audio
                    createdDecoders.append(decoder)
                    return decoder
                },
                audioRenderer: IRFFAudioRenderer()
            )
        )
        let original = ControlledFFPlayerDecoder(duration: 5)
        player.decoder = original
        player.state = .playing
        host.onStateChange = { state in
            guard state == .none else { return }
            host.onStateChange = nil
            host.contentURL = NSURL(
                fileURLWithPath: "/tmp/reentrant.mp4"
            )
            player.replaceVideo()
        }

        player.replaceVideo()

        XCTAssertEqual(
            factoryURLs.map(\.path),
            ["/tmp/reentrant.mp4"]
        )
        XCTAssertEqual(createdDecoders.count, 1)
        XCTAssertTrue(player.decoder === createdDecoders[0])
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertEqual(createdDecoders[0].openCount, 1)
        player.stop()
    }

    func testFacadeDeinitSilentlyClosesOwnedDecoderWithoutCycle() {
        let host = FFPlayerRuntimeHostSpy()
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        var player: IRFFPlayer? = IRFFPlayer.player(with: host)
        player?.decoder = decoder
        player?.state = .playing
        player?.progress = 2
        let eventCountBeforeDeinit = host.eventCount
        weak var weakPlayer: IRFFPlayer?
        weakPlayer = player

        player = nil

        XCTAssertNil(weakPlayer)
        XCTAssertEqual(host.eventCount, eventCountBeforeDeinit)
        XCTAssertEqual(decoder.closeCount, 1)
        XCTAssertNil(decoder.delegate)
    }

    func testFacadeDeinitDoesNotClearSharedPresentation() {
        let host = FFPlayerRuntimeHostSpy()
        let displayView = ClearCountingFFPlayerGLView(frame: .zero)
        host.displayView = displayView
        var player: IRFFPlayer? = IRFFPlayer.player(with: host)
        player?.decoder = ControlledFFPlayerDecoder(duration: 10)

        player = nil

        XCTAssertEqual(displayView.clearCount, 0)
    }

    func testStaleDecoderEventsCannotMutateReplacementRuntime() throws {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let first = ControlledFFPlayerDecoder(duration: 10)
        let second = ControlledFFPlayerDecoder(duration: 20)

        XCTAssertNotNil(runtime.adopt(first))
        let staleBridge = try XCTUnwrap(first.delegate)
        first.delegate?.decoder(first, didChangeValueOfProgress: 3)
        XCTAssertEqual(runtime.progress, 3)

        XCTAssertNotNil(runtime.adopt(second))
        staleBridge.decoder(first, didChangeValueOfProgress: 99)
        XCTAssertEqual(runtime.progress, 0)

        second.delegate?.decoder(
            second,
            didChangeValueOfProgress: 7
        )
        XCTAssertEqual(runtime.progress, 7)
        XCTAssertEqual(
            runtime.diagnostics.decoderSession.rejectedEventCount,
            1
        )
    }

    func testSnapshotReadsOnePreparedDecoderGenerationAndRealSeekingState() {
        let host = FFPlayerRuntimeHostSpy()
        let player = IRFFPlayer.player(with: host)
        let decoder = ControlledFFPlayerDecoder(
            duration: 10,
            presentationSize: CGSize(width: 1920, height: 1080),
            bitrate: 640
        )
        player.decoder = decoder
        decoder.setValue(true, forKey: "prepareToDecode")
        decoder.setValue(true, forKey: "seeking")
        player.state = .playing
        player.progress = 4
        player.playableTime = 6

        let backend: any IRPlaybackBackend = player
        let snapshot = backend.snapshot

        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(
            snapshot.presentationSize,
            CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(snapshot.bitrate, 640)
        XCTAssertEqual(snapshot.progress, 4)
        XCTAssertEqual(snapshot.duration, 10)
        XCTAssertEqual(snapshot.playableTime, 6)
        XCTAssertTrue(snapshot.isSeeking)
        XCTAssertTrue(player.seeking)
    }

    func testSeekDrainsAudioAndOnlyLatestCompletionResumesGraph() {
        let driver = TestAudioGraphDriver()
        let manager = makeTestAudioManager(driver: driver)
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(
            host: host,
            audioManager: manager
        )
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.playRequested = true
        runtime.state = .playing
        XCTAssertTrue(manager.playing)
        let initialStartCount = driver.startCount

        let frame = IRFFAudioFrame()
        runtime.currentAudioFrame = frame
        var results: [Bool] = []
        runtime.seek(to: 2) { results.append($0) }
        XCTAssertFalse(manager.playing)
        XCTAssertNil(runtime.currentAudioFrame)

        runtime.seek(to: 4) { results.append($0) }
        decoder.finishSeek(at: 0, result: true)
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                results.count == 1
            }
        )
        XCTAssertFalse(manager.playing)
        XCTAssertEqual(driver.startCount, initialStartCount)

        decoder.finishSeek(at: 1, result: true)
        XCTAssertTrue(
            waitUntil(timeout: 1) {
                manager.playing && results.count == 2
            }
        )
        XCTAssertEqual(driver.startCount, initialStartCount + 1)
        XCTAssertEqual(results, [true, true])
    }

    func testCloseIsSilentAndRejectsAllLaterCommandsAndEvents() throws {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        let staleBridge = try XCTUnwrap(decoder.delegate)
        runtime.state = .playing
        runtime.progress = 2
        let eventCountBeforeClose = host.eventCount

        XCTAssertTrue(runtime.close())
        XCTAssertFalse(runtime.close())
        staleBridge.decoder(decoder, didChangeValueOfProgress: 9)
        runtime.play()
        runtime.pause()
        runtime.progress = 8
        var seekResult: Bool?
        runtime.seek(to: 4) {
            seekResult = $0
        }

        XCTAssertEqual(host.eventCount, eventCountBeforeClose)
        XCTAssertEqual(seekResult, false)
        XCTAssertEqual(runtime.state, .none)
        XCTAssertEqual(runtime.progress, 0)
        XCTAssertNil(runtime.currentDecoder)
        XCTAssertTrue(runtime.diagnostics.isClosed)
        XCTAssertEqual(runtime.diagnostics.closeCount, 1)
        XCTAssertGreaterThanOrEqual(
            runtime.diagnostics.rejectedCommandCount,
            4
        )
    }

    func testFailureDoesNotPublishAcrossReentrantReplacement() throws {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let failed = ControlledFFPlayerDecoder(duration: 10)
        let replacement = ControlledFFPlayerDecoder(duration: 20)
        XCTAssertNotNil(runtime.adopt(failed))
        let failedBridge = try XCTUnwrap(failed.delegate)
        host.onStateChange = { state in
            guard state == .failed else { return }
            XCTAssertNotNil(runtime.adopt(replacement))
        }

        failedBridge.decoder(
            failed,
            didError: NSError(domain: "stale.failure", code: 7)
        )

        XCTAssertTrue(runtime.currentDecoder === replacement)
        XCTAssertEqual(runtime.state, .none)
        XCTAssertNil(host.error)
        XCTAssertEqual(host.failureCount, 0)
        XCTAssertEqual(failed.closeCount, 1)
    }

    func testReentrantReplacementDuringResetWinsRuntimeGeneration() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let original = ControlledFFPlayerDecoder(duration: 10)
        let reentrant = ControlledFFPlayerDecoder(duration: 20)
        let displaced = ControlledFFPlayerDecoder(duration: 30)
        XCTAssertNotNil(runtime.adopt(original))
        runtime.state = .playing
        host.onStateChange = { state in
            guard state == .none else { return }
            XCTAssertNotNil(runtime.adopt(reentrant))
        }

        let token = runtime.adopt(displaced)

        XCTAssertNil(token)
        XCTAssertTrue(runtime.currentDecoder === reentrant)
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertEqual(reentrant.closeCount, 0)
        XCTAssertEqual(displaced.closeCount, 0)
        XCTAssertEqual(runtime.diagnostics.rejectedCommandCount, 1)
    }

    func testDecoderOpenReentrantReplacementKeepsNewAudioSource() {
        let host = FFPlayerRuntimeHostSpy()
        let opening = ControlledFFPlayerDecoder(duration: 10)
        let replacement = ControlledFFPlayerDecoder(duration: 20)
        let runtime = IRFFPlayerRuntime(
            host: host,
            audioManager: nil,
            decoderFactory: {
                _, _, _, _, _ in opening
            }
        )
        opening.onOpen = {
            opening.delegate?.decoderWillOpenInputStream(opening)
        }
        host.onStateChange = { state in
            guard state == .buffering else { return }
            host.onStateChange = nil
            XCTAssertNotNil(runtime.adopt(replacement))
        }

        let token = runtime.activate(
            configuration: makeFFPlayerSessionConfiguration(),
            volume: 1
        )

        XCTAssertNil(token)
        XCTAssertTrue(runtime.currentDecoder === replacement)
        XCTAssertEqual(opening.closeCount, 1)
        XCTAssertTrue(runtime.audioRenderer.diagnostics.hasSource)
    }

    func testPlayIntentIsVisibleToSynchronousDecoderBufferingEvent() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.state = .buffering
        decoder.onResume = {
            decoder.delegate?.decoder(
                decoder,
                didChangeValueOfBuffering: false
            )
        }

        runtime.play()

        XCTAssertTrue(runtime.playRequested)
        XCTAssertEqual(runtime.state, .playing)
        XCTAssertFalse(host.states.contains(.readyToPlay))
    }

    func testReentrantPauseDuringResumeWinsPlaybackCommand() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.state = .readyToPlay
        decoder.onResume = {
            runtime.pause()
        }

        runtime.play()

        XCTAssertFalse(runtime.playRequested)
        XCTAssertEqual(runtime.state, .suspend)
        XCTAssertEqual(runtime.diagnostics.playbackCommandGeneration, 2)
    }

    func testReentrantPlayDuringPauseWinsPlaybackCommand() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.state = .playing
        runtime.playRequested = true
        decoder.onPause = {
            runtime.play()
        }

        runtime.pause()

        XCTAssertTrue(runtime.playRequested)
        XCTAssertEqual(runtime.state, .playing)
        XCTAssertEqual(runtime.diagnostics.playbackCommandGeneration, 2)
    }

    func testFinishedPlayDoesNotDuplicateDecoderRestartSeek() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.state = .finished
        decoder.onResume = {
            decoder.setValue(true, forKey: "seeking")
        }

        runtime.play()

        XCTAssertEqual(decoder.seekCount, 0)
        XCTAssertEqual(runtime.state, .playing)
        XCTAssertTrue(runtime.playRequested)
    }

    func testFinishedPlayRequestsRestartWhenDecoderDidNotStartOne() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 10)
        XCTAssertNotNil(runtime.adopt(decoder))
        runtime.state = .finished

        runtime.play()

        XCTAssertEqual(decoder.seekCount, 1)
        XCTAssertEqual(runtime.state, .playing)
        XCTAssertTrue(runtime.playRequested)
    }

    func testConcurrentCommandsAndEventsRemainSerialized() {
        let host = FFPlayerRuntimeHostSpy()
        let runtime = IRFFPlayerRuntime(host: host, audioManager: nil)
        let decoder = ControlledFFPlayerDecoder(duration: 100)
        XCTAssertNotNil(runtime.adopt(decoder))
        let delegate = decoder.delegate

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            switch index % 4 {
            case 0:
                runtime.play()
            case 1:
                runtime.pause()
            case 2:
                runtime.progress = TimeInterval(index)
            default:
                delegate?.decoder(
                    decoder,
                    didChangeValueOfProgress: TimeInterval(index)
                )
            }
            _ = runtime.snapshot
        }

        runtime.state = .playing
        runtime.pause()
        runtime.progress = 42
        let snapshot = runtime.snapshot

        XCTAssertEqual(snapshot.state, .suspend)
        XCTAssertEqual(snapshot.progress, 42)
        XCTAssertEqual(snapshot.duration, 100)
        XCTAssertGreaterThan(
            runtime.diagnostics.executor.entryCount,
            400
        )
        XCTAssertEqual(
            runtime.diagnostics.decoderSession.acceptedEventCount,
            50
        )
    }

    func testRealAudioEOFIsReconciledOutsideRenderCallback()
        throws
    {
        let url = try makeTinyPCM16WAVFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let driver = TestAudioGraphDriver()
        let manager = makeTestAudioManager(driver: driver)
        let host = FFPlayerRuntimeHostSpy()
        host.contentURL = url as NSURL
        host.displayView = IRGLView(frame: .zero)
        host.manager = manager
        let player = IRFFPlayer.player(with: host)
        addTeardownBlock {
            player.stop()
        }

        player.replaceVideo()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                player.decoder?.prepareToDecode == true &&
                    player.decoder?.endOfFile == true
            }
        )

        player.play()
        XCTAssertTrue(
            waitUntil(timeout: 2) {
                manager.playing
            }
        )

        let renderReturned = expectation(
            description: "real audio render returned"
        )
        DispatchQueue.global(qos: .userInitiated).async {
            var samples = [Float](
                repeating: 0,
                count: 2_048 * 2
            )
            withInterleavedAudioBufferList(
                values: &samples,
                channels: 2
            ) { bufferList in
                _ = manager.renderFrames(
                    2_048,
                    ioData: bufferList
                )
            }
            renderReturned.fulfill()
        }
        wait(for: [renderReturned], timeout: 2)

        XCTAssertTrue(
            waitUntil(timeout: 2) {
                player.state == .finished
            }
        )
        XCTAssertFalse(manager.playing)
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.005)
            )
        }
        return predicate()
    }
}

final class IRFFPlayerPresentationOwnerTests: XCTestCase {
    func testConfigurationMapsHardwareAndEveryVideoMode() {
        let videoTypes: [IRVideoType] = [
            .normal,
            .vr,
            .fisheye,
            .pano,
            .custom
        ]

        for videoType in videoTypes {
            let software = IRFFPlayerPresentation.configuration(
                hardwareDecoderEnabled: false,
                videoType: videoType
            )
            let hardware = IRFFPlayerPresentation.configuration(
                hardwareDecoderEnabled: true,
                videoType: videoType
            )

            XCTAssertEqual(software.pixelFormat, .YUV_IRPixelFormat)
            XCTAssertEqual(hardware.pixelFormat, .NV12_IRPixelFormat)
            let expectedRenderer: IRDisplayRendererType =
                videoType == .vr
                ? .FFmpegPixelBufferVR
                : .FFmpegPixelBuffer
            XCTAssertEqual(software.rendererType, expectedRenderer)
            XCTAssertEqual(hardware.rendererType, expectedRenderer)
        }
    }

    func testApplyFromBackgroundCompletesMainPresentationTransaction() {
        let view = IRGLView(frame: .zero)
        let configuration = IRFFPlayerPresentation.configuration(
            hardwareDecoderEnabled: true,
            videoType: .vr
        )
        let applied = expectation(description: "presentation applied")

        DispatchQueue.global().async {
            configuration.apply(to: view)
            applied.fulfill()
        }

        wait(for: [applied], timeout: 2)
        XCTAssertEqual(view.irPixelFormat, .NV12_IRPixelFormat)
        XCTAssertEqual(view.rendererType, .FFmpegPixelBufferVR)
    }
}

private func makeFFPlayerSessionConfiguration(
    contentHeaders:
        [String: String] = [:],
    source: IRFFVideoInput? = nil,
    videoOutput: (any IRFFDecoderVideoOutput)? = nil,
    audioOutput: (any IRFFDecoderAudioOutput)? = nil,
    hardwareDecoderEnabled: Bool = false,
    isLiveStream: Bool = false,
    minimumBufferedDuration: TimeInterval = 2
) -> IRFFPlayerDecoderSession.Configuration {
    IRFFPlayerDecoderSession.Configuration(
        contentURL: URL(fileURLWithPath: "/tmp/runtime-owner.mp4"),
        videoFormat: .mpeg4,
        contentHeaders:
            contentHeaders,
        videoOutput: videoOutput,
        audioOutput: audioOutput,
        source: source,
        hardwareDecoderEnabled: hardwareDecoderEnabled,
        isLiveStream: isLiveStream,
        minimumBufferedDuration: minimumBufferedDuration
    )
}

private final class ControlledFFPlayerDecoder:
    IRFFDecoder,
    @unchecked Sendable
{
    private let controlLock = NSLock()
    private let fixedDuration: TimeInterval
    private let fixedPresentationSize: CGSize
    private let fixedBitrate: TimeInterval
    private var storedOpenCount = 0
    private var storedCloseCount = 0
    private var storedPauseCount = 0
    private var storedResumeCount = 0
    private var seekCompletions: [((Bool) -> Void)?] = []

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?

    init(
        duration: TimeInterval = 0,
        presentationSize: CGSize = .zero,
        bitrate: TimeInterval = 0
    ) {
        self.fixedDuration = duration
        self.fixedPresentationSize = presentationSize
        self.fixedBitrate = bitrate
        super.init(
            contentURL: URL(fileURLWithPath: "/tmp/controlled.mp4"),
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

    var openCount: Int {
        controlLock.lock()
        defer { controlLock.unlock() }
        return storedOpenCount
    }

    var closeCount: Int {
        controlLock.lock()
        defer { controlLock.unlock() }
        return storedCloseCount
    }

    var seekCount: Int {
        controlLock.lock()
        defer { controlLock.unlock() }
        return seekCompletions.count
    }

    override func open() {
        controlLock.lock()
        storedOpenCount += 1
        let callback = onOpen
        controlLock.unlock()
        callback?()
    }

    override func closeFile() {
        controlLock.lock()
        storedCloseCount += 1
        let callback = onClose
        controlLock.unlock()
        callback?()
    }

    override func pause() {
        controlLock.lock()
        storedPauseCount += 1
        let callback = onPause
        controlLock.unlock()
        callback?()
    }

    override func resume() {
        controlLock.lock()
        storedResumeCount += 1
        let callback = onResume
        controlLock.unlock()
        callback?()
    }

    override func seek(
        to time: TimeInterval,
        completeHandler: ((Bool) -> Void)? = nil
    ) {
        controlLock.lock()
        seekCompletions.append(completeHandler)
        controlLock.unlock()
    }

    func finishSeek(at index: Int, result: Bool) {
        controlLock.lock()
        let completion = seekCompletions.indices.contains(index)
            ? seekCompletions[index]
            : nil
        controlLock.unlock()
        completion?(result)
    }
}

private final class FFPlayerEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func record(_ event: IRFFPlayerDecoderSession.Event) {
        let value: String
        switch event {
        case .willOpenInput:
            value = "willOpenInput"
        case .prepared:
            value = "prepared"
        case .endOfFile:
            value = "endOfFile"
        case .playbackFinished:
            value = "playbackFinished"
        case .failed(let error):
            value = "failed:\(error.code)"
        case .bufferingChanged(let buffering):
            value = "buffering:\(buffering)"
        case .bufferedDurationChanged(let duration):
            value = "bufferedDuration:\(duration)"
        case .progressChanged(let progress):
            value = "progress:\(progress)"
        }
        lock.lock()
        storedEvents.append(value)
        lock.unlock()
    }
}

private final class FFPlayerBoolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: Bool) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

private final class FFPlayerIntRecorder: @unchecked Sendable {
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

private final class FFPlayerVideoOutputProbe:
    NSObject,
    IRFFDecoderVideoOutput
{}

private final class ClearCountingFFPlayerGLView: IRGLView {
    private(set) var clearCount = 0

    override func cleanEmptyBuffer() {
        clearCount += 1
    }
}

private final class FFPlayerAudioOutputProbe:
    NSObject,
    IRFFDecoderAudioOutput
{
    let numberOfChannels: UInt32 = 2
    let samplingRate: Float64 = 48_000
}

private final class FFPlayerRuntimeHostSpy:
    IRPlaybackBackendHost,
    @unchecked Sendable
{
    var contentURL: NSURL? = NSURL(
        fileURLWithPath: "/tmp/runtime-owner.mp4"
    )
    var contentHeaders: [String: String]?
    var videoType: IRVideoType = .normal
    var videoInput: IRFFVideoInput?
    var decoder = IRPlayerDecoder.FFmpegDecoder()
    var displayView: IRGLView?
    var manager: IRAudioManager?
    var volume: CGFloat = 1
    var playableBufferInterval: TimeInterval = 2
    var isLiveStream = false

    private let eventLock = NSLock()
    private var storedError: IRError?
    private var storedStates: [IRPlayerState] = []
    private var storedProgressUpdates = 0
    private var storedPlayableUpdates = 0
    private var storedLastProgress:
        (current: TimeInterval, total: TimeInterval)?
    private var storedLastPlayable:
        (current: TimeInterval, total: TimeInterval)?
    private var storedFailures = 0
    var onStateChange: ((IRPlayerState) -> Void)?

    var error: IRError? {
        get {
            eventLock.lock()
            defer { eventLock.unlock() }
            return storedError
        }
        set {
            eventLock.lock()
            storedError = newValue
            eventLock.unlock()
        }
    }

    var eventCount: Int {
        eventLock.lock()
        defer { eventLock.unlock() }
        return storedStates.count +
            storedProgressUpdates +
            storedPlayableUpdates +
            storedFailures
    }

    var failureCount: Int {
        eventLock.lock()
        defer { eventLock.unlock() }
        return storedFailures
    }

    var lastProgress:
        (current: TimeInterval, total: TimeInterval)?
    {
        eventLock.lock()
        defer { eventLock.unlock() }
        return storedLastProgress
    }

    var lastPlayable:
        (current: TimeInterval, total: TimeInterval)?
    {
        eventLock.lock()
        defer { eventLock.unlock() }
        return storedLastPlayable
    }

    var states: [IRPlayerState] {
        eventLock.lock()
        defer { eventLock.unlock() }
        return storedStates
    }

    func playbackBackendDidChangeState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        eventLock.lock()
        storedStates.append(current)
        let callback = onStateChange
        eventLock.unlock()
        callback?(current)
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        eventLock.lock()
        storedProgressUpdates += 1
        storedLastProgress = (current, total)
        eventLock.unlock()
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        eventLock.lock()
        storedPlayableUpdates += 1
        storedLastPlayable = (current, total)
        eventLock.unlock()
    }

    func playbackBackendDidFail(_ error: IRError) {
        eventLock.lock()
        storedFailures += 1
        eventLock.unlock()
    }
}

private func withInterleavedAudioBufferList<Element>(
    values: inout [Element],
    channels: UInt32,
    body: (UnsafeMutablePointer<AudioBufferList>) throws -> Void
) rethrows {
    try values.withUnsafeMutableBufferPointer { buffer in
        guard let address = buffer.baseAddress else { return }
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(list.unsafeMutablePointer) }
        list.count = 1
        list[0] = AudioBuffer(
            mNumberChannels: channels,
            mDataByteSize: UInt32(
                buffer.count * MemoryLayout<Element>.stride
            ),
            mData: address
        )
        try body(list.unsafeMutablePointer)
    }
}
