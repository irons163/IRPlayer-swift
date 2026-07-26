import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecoderRuntimeStateTests: XCTestCase {
    func testScalarChangesAreAtomicAndSuppressDuplicates() {
        let state = IRFFDecoderRuntimeState()

        XCTAssertEqual(
            state.setProgress(4),
            IRFFDecoderRuntimeState.Change(previous: 0, current: 4)
        )
        XCTAssertNil(state.setProgress(4))
        XCTAssertEqual(
            state.setBuffering(true),
            IRFFDecoderRuntimeState.Change(previous: false, current: true)
        )
        XCTAssertEqual(
            state.setAudioTimeClock(3.5),
            IRFFDecoderRuntimeState.Change(previous: 0, current: 3.5)
        )

        let snapshot = state.snapshot
        XCTAssertEqual(snapshot.progress, 4)
        XCTAssertTrue(snapshot.buffering)
        XCTAssertEqual(snapshot.audioTimeClock, 3.5)
        XCTAssertFalse(snapshot.closed)
        XCTAssertFalse(snapshot.hasError)
    }

    func testBufferedDurationPreservesRequestedChangeAfterNormalization() {
        let state = IRFFDecoderRuntimeState()

        let change = state.applyBufferedDuration(
            requestedValue: 0.000_000_1,
            normalizedValue: 0
        )

        XCTAssertEqual(change?.previous, 0)
        XCTAssertEqual(change?.current, 0)
        XCTAssertEqual(state.snapshot.bufferedDuration, 0)
        XCTAssertNil(
            state.applyBufferedDuration(
                requestedValue: 0,
                normalizedValue: 0
            )
        )
    }

    func testConcurrentCloseElectsExactlyOneCleanupOwner() {
        let state = IRFFDecoderRuntimeState()
        let resultLock = NSLock()
        var ownershipCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard state.beginClose() else { return }
            resultLock.lock()
            ownershipCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(ownershipCount, 1)
        XCTAssertTrue(state.snapshot.closed)
        XCTAssertFalse(state.beginClose())
    }

    func testPreparedTransitionCannotPublishAfterClose() {
        let state = IRFFDecoderRuntimeState()

        XCTAssertTrue(state.markPreparedIfOpen())
        XCTAssertTrue(state.snapshot.prepareToDecode)
        XCTAssertTrue(state.beginClose())
        XCTAssertFalse(state.markPreparedIfOpen())

        let closedBeforePrepare = IRFFDecoderRuntimeState()
        XCTAssertTrue(closedBeforePrepare.beginClose())
        XCTAssertFalse(closedBeforePrepare.markPreparedIfOpen())
        XCTAssertFalse(closedBeforePrepare.snapshot.prepareToDecode)
    }

    func testSeekReplacementAndConsumptionAreDeterministic() {
        let state = IRFFDecoderRuntimeState()
        var firstResults: [Bool] = []
        var secondResults: [Bool] = []

        let first = state.beginSeek(to: 2) { firstResults.append($0) }
        XCTAssertEqual(first?.progressChange?.current, 2)
        XCTAssertNil(first?.displacedCompletion)
        XCTAssertEqual(state.snapshot.progress, 2)
        XCTAssertTrue(state.snapshot.seeking)

        let second = state.beginSeek(to: 8) { secondResults.append($0) }
        second?.displacedCompletion?(false)
        XCTAssertEqual(firstResults, [false])
        XCTAssertEqual(second?.progressChange?.previous, 2)
        XCTAssertEqual(second?.progressChange?.current, 8)

        let request = state.takePendingSeek()
        XCTAssertEqual(request?.target, 8)
        XCTAssertTrue(state.snapshot.seeking)
        XCTAssertNil(state.takePendingSeek())

        let completion = request.flatMap(state.finishSeek)
        completion?(true)
        XCTAssertFalse(state.snapshot.seeking)
        XCTAssertEqual(secondResults, [true])
    }

    func testSeekAdmissionAdvancesDecodeGenerationAtomically() {
        let state = IRFFDecoderRuntimeState()
        XCTAssertEqual(
            state.snapshot.decodeGeneration,
            0
        )
        XCTAssertTrue(
            state.acceptsDecodeGeneration(0)
        )

        let first = state.beginSeek(
            to: 2,
            completion: nil
        )
        XCTAssertEqual(
            first?.decodeGeneration,
            1
        )
        XCTAssertFalse(
            state.acceptsDecodeGeneration(0)
        )
        XCTAssertTrue(
            state.acceptsDecodeGeneration(1)
        )
        XCTAssertEqual(
            state.takePendingSeek()?
                .decodeGeneration,
            1
        )

        let second = state.beginSeek(
            to: 4,
            completion: nil
        )
        XCTAssertEqual(
            second?.decodeGeneration,
            2
        )
        XCTAssertFalse(
            state.acceptsDecodeGeneration(1)
        )
        XCTAssertTrue(
            state.acceptsDecodeGeneration(2)
        )
    }

    func testSeekAtEOFAtomicallyClearsTerminalStateAndRequestsRestart() {
        let state = IRFFDecoderRuntimeState()
        _ = state.setEndOfFile(true)
        _ = state.setPlaybackFinished(true)

        let result = state.beginSeek(
            to: 3,
            completion: nil
        )

        XCTAssertEqual(
            result?.needsWorkerRestart,
            true
        )
        let snapshot = state.snapshot
        XCTAssertFalse(snapshot.endOfFile)
        XCTAssertFalse(
            snapshot.playbackFinished
        )
        XCTAssertTrue(snapshot.seeking)
        XCTAssertEqual(
            snapshot.decodeGeneration,
            result?.decodeGeneration
        )
    }

    func testStaleGenerationCannotCommitEOFFailureOrNotification() {
        let state = IRFFDecoderRuntimeState()
        let staleGeneration =
            state.snapshot.decodeGeneration
        var eofNotificationCount = 0
        var errorNotificationCount = 0
        _ = state.beginSeek(
            to: 5,
            completion: nil
        )

        XCTAssertFalse(
            state.commitEndOfFile(
                generation: staleGeneration,
                notification: {
                    eofNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            state.commitDecodeError(
                NSError(
                    domain: "stale-drain",
                    code: 1
                ),
                generation: staleGeneration,
                notification: {
                    errorNotificationCount += 1
                }
            )
        )

        XCTAssertEqual(
            eofNotificationCount,
            0
        )
        XCTAssertEqual(
            errorNotificationCount,
            0
        )
        XCTAssertFalse(state.snapshot.endOfFile)
        XCTAssertFalse(state.snapshot.hasError)
    }

    func testTerminalCommitIsFirstWinsInBothDirections() {
        let errorFirst = IRFFDecoderRuntimeState()
        var errorNotificationCount = 0
        var eofAfterErrorNotificationCount = 0
        let firstError = NSError(
            domain: "first-error",
            code: 1
        )

        XCTAssertTrue(
            errorFirst.commitDecodeError(
                firstError,
                generation: 0,
                notification: {
                    errorNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            errorFirst.commitDecodeError(
                NSError(
                    domain: "duplicate-error",
                    code: 2
                ),
                generation: 0,
                notification: {
                    errorNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            errorFirst.commitEndOfFile(
                generation: 0,
                notification: {
                    eofAfterErrorNotificationCount += 1
                }
            )
        )
        XCTAssertEqual(
            errorFirst.error as NSError?,
            firstError
        )
        XCTAssertFalse(errorFirst.snapshot.endOfFile)
        XCTAssertEqual(errorNotificationCount, 1)
        XCTAssertEqual(eofAfterErrorNotificationCount, 0)

        let eofFirst = IRFFDecoderRuntimeState()
        var eofNotificationCount = 0
        var errorAfterEOFNotificationCount = 0
        XCTAssertTrue(
            eofFirst.commitEndOfFile(
                generation: 0,
                notification: {
                    eofNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            eofFirst.commitEndOfFile(
                generation: 0,
                notification: {
                    eofNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            eofFirst.commitDecodeError(
                NSError(
                    domain: "late-error",
                    code: 3
                ),
                generation: 0,
                notification: {
                    errorAfterEOFNotificationCount += 1
                }
            )
        )
        XCTAssertTrue(eofFirst.snapshot.endOfFile)
        XCTAssertNil(eofFirst.error)
        XCTAssertEqual(eofNotificationCount, 1)
        XCTAssertEqual(errorAfterEOFNotificationCount, 0)
    }

    func testConcurrentDecodeErrorsElectExactlyOneOwner() {
        let state = IRFFDecoderRuntimeState()
        let ownershipCount = LockedFailureCount()
        let notificationCount = LockedFailureCount()

        DispatchQueue.concurrentPerform(
            iterations: 100
        ) { index in
            if state.commitDecodeError(
                NSError(
                    domain: "concurrent-error",
                    code: index
                ),
                generation: 0,
                notification: {
                    notificationCount.increment()
                }
            ) {
                ownershipCount.increment()
            }
        }

        XCTAssertEqual(ownershipCount.value, 1)
        XCTAssertEqual(notificationCount.value, 1)
        XCTAssertNotNil(state.error)
        XCTAssertFalse(state.snapshot.endOfFile)
    }

    func testStaleVideoMaintenanceCannotMutateOrNotify() {
        let state = IRFFDecoderRuntimeState()
        _ = state.setBufferedDuration(3)
        let staleGeneration =
            state.snapshot.decodeGeneration
        var bufferedNotificationCount = 0
        var bufferingNotificationCount = 0
        var followupNotificationCount = 0
        _ = state.beginSeek(
            to: 5,
            completion: nil
        )

        XCTAssertFalse(
            state.commitBufferedDuration(
                0.000_000_1,
                playbackDuration: 9,
                generation: staleGeneration,
                currentTime: 100,
                notification: { _ in
                    bufferedNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            state.commitVideoBufferingStatus(
                generation: staleGeneration,
                currentTime: 100,
                notification: { _ in
                    bufferingNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            state.notifyIfCurrentDecodeGeneration(
                staleGeneration,
                notification: {
                    followupNotificationCount += 1
                }
            )
        )

        let snapshot = state.snapshot
        XCTAssertEqual(snapshot.bufferedDuration, 3)
        XCTAssertFalse(snapshot.buffering)
        XCTAssertFalse(snapshot.playbackFinished)
        XCTAssertEqual(snapshot.progress, 5)
        XCTAssertEqual(bufferedNotificationCount, 0)
        XCTAssertEqual(bufferingNotificationCount, 0)
        XCTAssertEqual(followupNotificationCount, 0)
    }

    func testVideoBufferedDurationCommitsBeforeNotificationAndSuppressesDisplacedEvents() {
        let state = IRFFDecoderRuntimeState()
        _ = state.setEndOfFile(true)
        _ = state.setBuffering(true)
        let generation =
            state.snapshot.decodeGeneration
        var observedCommittedState = false
        var deliveredEvents: [String] = []

        XCTAssertTrue(
            state.commitBufferedDuration(
                0.000_000_1,
                playbackDuration: 9,
                generation: generation,
                currentTime: 100,
                notification: { commit in
                    let committed = state.snapshot
                    observedCommittedState =
                        committed.bufferedDuration == 0 &&
                        committed.progress == 9 &&
                        committed.playbackFinished &&
                        !committed.buffering
                    deliveredEvents.append("buffered")

                    _ = state.beginSeek(
                        to: 4,
                        completion: nil
                    )
                    _ = state.setBufferedDuration(7)
                    _ = state.setBuffering(true)

                    if commit.progressChange != nil {
                        _ = state.notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                deliveredEvents.append("progress")
                            }
                        )
                    }
                    if commit.didFinishPlayback {
                        _ = state.notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                deliveredEvents.append("finished")
                            }
                        )
                    }
                    if commit.bufferingChange != nil {
                        _ = state.notifyIfCurrentDecodeGeneration(
                            generation,
                            notification: {
                                deliveredEvents.append("buffering")
                            }
                        )
                    }
                }
            )
        )

        let current = state.snapshot
        XCTAssertTrue(observedCommittedState)
        XCTAssertEqual(deliveredEvents, ["buffered"])
        XCTAssertEqual(
            current.decodeGeneration,
            generation + 1
        )
        XCTAssertEqual(current.progress, 4)
        XCTAssertEqual(current.bufferedDuration, 7)
        XCTAssertFalse(current.playbackFinished)
        XCTAssertTrue(current.buffering)
    }

    func testVideoBufferingNotificationCanReenterSeekWithoutOldWriteback() {
        let state = IRFFDecoderRuntimeState()
        let generation =
            state.snapshot.decodeGeneration
        var notificationCount = 0

        XCTAssertTrue(
            state.commitVideoBufferingStatus(
                generation: generation,
                currentTime: 100,
                notification: { change in
                    notificationCount += 1
                    XCTAssertEqual(
                        change,
                        .init(
                            previous: false,
                            current: true
                        )
                    )
                    XCTAssertTrue(
                        state.snapshot.buffering
                    )
                    _ = state.beginSeek(
                        to: 6,
                        completion: nil
                    )
                    _ = state.setBuffering(false)
                }
            )
        )

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(
            state.snapshot.decodeGeneration,
            generation + 1
        )
        XCTAssertEqual(state.snapshot.progress, 6)
        XCTAssertFalse(state.snapshot.buffering)
    }

    func testEOFNotificationCanReenterSeekWithoutPublishingOldTerminalState() {
        let state = IRFFDecoderRuntimeState()
        let generation =
            state.snapshot.decodeGeneration
        var restartWasRequested = false

        XCTAssertTrue(
            state.commitEndOfFile(
                generation: generation,
                notification: {
                    restartWasRequested =
                        state.beginSeek(
                            to: 8,
                            completion: nil
                        )?.needsWorkerRestart
                        == true
                }
            )
        )

        XCTAssertTrue(restartWasRequested)
        XCTAssertFalse(state.snapshot.endOfFile)
        XCTAssertTrue(state.snapshot.seeking)
        XCTAssertEqual(
            state.snapshot.decodeGeneration,
            generation + 1
        )
    }

    func testSeekCompletionIsReturnedOnlyAfterStateCommit() throws {
        let state = IRFFDecoderRuntimeState()
        var callbackObservedCommittedState = false
        _ = state.setEndOfFile(true)
        _ = state.setPlaybackFinished(true)
        _ = state.beginSeek(to: 7) { result in
            let snapshot = state.snapshot
            callbackObservedCommittedState =
                result &&
                !snapshot.endOfFile &&
                !snapshot.playbackFinished &&
                snapshot.buffering &&
                !snapshot.seeking &&
                snapshot.audioTimeClock == 7
        }
        let request = try XCTUnwrap(
            state.takePendingSeek()
        )
        let commit = try XCTUnwrap(
            state.commitSeek(
                request,
                transition:
                    IRFFDecoder
                        .SeekCompletionTransition(
                            endOfFile: false,
                            playbackFinished: false,
                            buffering: true,
                            videoPaused: false,
                            videoEndOfFile: false,
                            seekToTime: 0,
                            audioTimeClock: 7,
                            shouldClearFrames: true
                        ),
                bufferingStartTime: 123
            )
        )

        XCTAssertFalse(
            callbackObservedCommittedState
        )
        XCTAssertEqual(
            commit.bufferingChange,
            .init(previous: false, current: true)
        )
        XCTAssertEqual(
            state.snapshot.bufferingStartTime,
            123
        )

        commit.completion?(true)

        XCTAssertTrue(
            callbackObservedCommittedState
        )
    }

    func testSeekStartedDuringActiveSeekRemainsPending() {
        let state = IRFFDecoderRuntimeState()
        var firstResults: [Bool] = []
        var secondResults: [Bool] = []
        _ = state.beginSeek(to: 5) { firstResults.append($0) }
        let activeRequest = state.takePendingSeek()

        _ = state.beginSeek(to: 9) { secondResults.append($0) }
        let activeCompletion = activeRequest.flatMap(state.finishSeek)
        activeCompletion?(true)

        XCTAssertEqual(firstResults, [true])
        XCTAssertTrue(state.snapshot.seeking)
        let pendingRequest = state.takePendingSeek()
        XCTAssertEqual(pendingRequest?.target, 9)
        let pendingCompletion = pendingRequest.flatMap(state.finishSeek)
        pendingCompletion?(true)
        XCTAssertEqual(secondResults, [true])
        XCTAssertFalse(state.snapshot.seeking)
    }

    func testClosingRejectsAndCancelsPendingAndActiveSeeksExactlyOnce() {
        let state = IRFFDecoderRuntimeState()
        var activeResults: [Bool] = []
        var pendingResults: [Bool] = []
        _ = state.beginSeek(to: 5) { activeResults.append($0) }
        let activeRequest = state.takePendingSeek()
        _ = state.beginSeek(to: 7) { pendingResults.append($0) }

        XCTAssertTrue(state.beginClose())
        let completions = state.cancelSeeks()
        completions.forEach { $0(false) }

        XCTAssertEqual(activeResults, [false])
        XCTAssertEqual(pendingResults, [false])
        XCTAssertTrue(state.cancelSeeks().isEmpty)
        XCTAssertNil(activeRequest.flatMap(state.finishSeek))
        XCTAssertNil(state.beginSeek(to: 9, completion: nil))
        XCTAssertFalse(state.snapshot.seeking)
    }

    func testFrameReferencesAreProtectedAndClearedTogether() {
        let state = IRFFDecoderRuntimeState()
        let videoFrame = IRFFVideoFrame()
        let audioFrame = IRFFAudioFrame()

        state.currentVideoFrame = videoFrame
        state.currentAudioFrame = audioFrame

        XCTAssertTrue(state.currentVideoFrame === videoFrame)
        XCTAssertTrue(state.currentAudioFrame === audioFrame)

        state.clearFrames()

        XCTAssertNil(state.currentVideoFrame)
        XCTAssertNil(state.currentAudioFrame)
    }

    func testDeliveredVideoFrameCommitsBeforeProgressNotification() {
        let state = IRFFDecoderRuntimeState()
        let frame = IRFFVideoFrame()
        frame.position = 8
        var notificationObservedCommit =
            false

        XCTAssertTrue(
            state.commitDeliveredVideoFrame(
                frame,
                generation: 0,
                progress: frame.position,
                playbackDuration: 30,
                delivery: { $0 === frame },
                notification: { change in
                    notificationObservedCommit =
                        change.current == 8 &&
                        state.currentVideoFrame
                            === frame &&
                        state.snapshot.progress == 8
                }
            )
        )

        XCTAssertTrue(
            state.currentVideoFrame === frame
        )
        XCTAssertEqual(state.snapshot.progress, 8)
        XCTAssertTrue(notificationObservedCommit)
    }

    func testDeliveredVideoFrameReentrantSeekCannotPublishStaleFrame() {
        let state = IRFFDecoderRuntimeState()
        let staleFrame = IRFFVideoFrame()
        staleFrame.position = 9
        let replacementFrame = IRFFVideoFrame()
        replacementFrame.position = 4
        let generation =
            state.snapshot.decodeGeneration
        var progressNotificationCount = 0

        let committed =
            state.commitDeliveredVideoFrame(
                staleFrame,
                generation: generation,
                progress: staleFrame.position,
                playbackDuration: 30,
                delivery: { _ in
                    _ = state.beginSeek(
                        to: 4,
                        completion: nil
                    )
                    state.currentVideoFrame =
                        replacementFrame
                    return true
                },
                notification: { _ in
                    progressNotificationCount += 1
                }
            )
        if !committed {
            staleFrame.cancel()
        }

        XCTAssertFalse(committed)
        XCTAssertEqual(
            state.snapshot.decodeGeneration,
            generation + 1
        )
        XCTAssertEqual(state.snapshot.progress, 4)
        XCTAssertTrue(
            state.currentVideoFrame
                === replacementFrame
        )
        XCTAssertEqual(progressNotificationCount, 0)
    }

    func testStaleDisplayReplayAndClearCannotTouchNewGeneration() {
        let state = IRFFDecoderRuntimeState()
        let oldFrame = IRFFVideoFrame()
        state.currentVideoFrame = oldFrame
        let staleGeneration =
            state.snapshot.decodeGeneration
        _ = state.beginSeek(
            to: 5,
            completion: nil
        )
        let replacementFrame = IRFFVideoFrame()
        state.currentVideoFrame =
            replacementFrame
        var replayCount = 0

        XCTAssertFalse(
            state.replayCurrentVideoFrame(
                generation: staleGeneration,
                delivery: { _ in
                    replayCount += 1
                    return true
                }
            )
        )
        XCTAssertFalse(
            state.clearCurrentVideoFrame(
                generation: staleGeneration
            )
        )

        XCTAssertEqual(replayCount, 0)
        XCTAssertTrue(
            state.currentVideoFrame
                === replacementFrame
        )
        XCTAssertEqual(state.snapshot.progress, 5)
    }

    func testAudioFetchAndDeferredRecycleHaveSingleOwner() {
        let state = IRFFDecoderRuntimeState()
        let first = IRFFAudioFrame()
        let second = IRFFAudioFrame()
        var dequeueCount = 0

        let fetched = state.tryFetchAudioFrame { _ in
            dequeueCount += 1
            return IRFFAudioFrameTransfer(
                frame: first,
                position: 2,
                duration: 0.25,
                size: 16
            )
        }
        XCTAssertTrue(fetched?.frame === first)
        XCTAssertEqual(fetched?.byteCount, 16)
        XCTAssertTrue(state.currentAudioFrame === first)
        XCTAssertEqual(state.activeAudioFrameDuration, 0.25)

        XCTAssertNil(
            state.tryFetchAudioFrame { _ in
                dequeueCount += 1
                return IRFFAudioFrameTransfer(
                    frame: second,
                    position: 3,
                    duration: 0.25,
                    size: 24
                )
            }
        )
        XCTAssertEqual(dequeueCount, 1)

        state.clearFrames()
        XCTAssertTrue(state.currentAudioFrame === first)
        XCTAssertEqual(state.activeAudioFrameDuration, 0)
        XCTAssertTrue(
            state.tryFinishAudioFrame(ObjectIdentifier(first))
        )
        XCTAssertNil(state.currentAudioFrame)

        XCTAssertTrue(
            state.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: second,
                    position: 3,
                    duration: 0.25,
                    size: 24
                )
            }?.frame === second
        )
        XCTAssertTrue(
            state.tryFinishAudioFrame(ObjectIdentifier(second))
        )
        XCTAssertTrue(state.takeFinishedAudioFrame() === first)
        XCTAssertTrue(state.takeFinishedAudioFrame() === second)
        XCTAssertNil(state.takeFinishedAudioFrame())
    }

    func testSeekClearsGenerationOwnedPendingAudioProgress() {
        let state = IRFFDecoderRuntimeState()
        let frame = IRFFAudioFrame()
        let generation =
            state.snapshot.decodeGeneration
        XCTAssertNotNil(
            state.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: frame,
                    position: 2,
                    duration: 0.25,
                    size: 16
                )
            }
        )
        _ = state.beginSeek(
            to: 7,
            completion: nil
        )
        var notificationCount = 0

        XCTAssertFalse(
            state.commitPendingAudioProgress(
                generation: generation,
                playbackDuration: 30,
                notification: { _ in
                    notificationCount += 1
                }
            )
        )
        XCTAssertEqual(state.snapshot.progress, 7)
        XCTAssertEqual(notificationCount, 0)
    }

    func testPendingAudioProgressCommitsNormalizedValueExactlyOnce() {
        let state = IRFFDecoderRuntimeState()
        XCTAssertNotNil(
            state.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: IRFFAudioFrame(),
                    position: 40,
                    duration: 0.25,
                    size: 16
                )
            }
        )
        var notifications: [TimeInterval] = []

        XCTAssertTrue(
            state.commitPendingAudioProgress(
                generation: 0,
                playbackDuration: 30,
                notification: {
                    notifications.append(
                        $0.current
                    )
                }
            )
        )
        XCTAssertFalse(
            state.commitPendingAudioProgress(
                generation: 0,
                playbackDuration: 30,
                notification: {
                    notifications.append(
                        $0.current
                    )
                }
            )
        )
        XCTAssertEqual(state.snapshot.progress, 30)
        XCTAssertEqual(notifications, [30])
    }

    func testAudioProgressAndDurationRejectSeekingAndError() {
        let seekingState = IRFFDecoderRuntimeState()
        let seek = seekingState.beginSeek(
            to: 6,
            completion: nil
        )
        guard let seekingGeneration =
                seek?.decodeGeneration else {
            XCTFail("Seek should advance generation")
            return
        }
        XCTAssertNotNil(
            seekingState.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: IRFFAudioFrame(),
                    position: 9,
                    duration: 0.25,
                    size: 16
                )
            }
        )
        var seekingNotificationCount = 0
        XCTAssertFalse(
            seekingState.commitPendingAudioProgress(
                generation: seekingGeneration,
                playbackDuration: 30,
                notification: { _ in
                    seekingNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            seekingState.commitBufferedDuration(
                4,
                playbackDuration: 30,
                generation: seekingGeneration,
                currentTime: 100,
                notification: { _ in
                    seekingNotificationCount += 1
                }
            )
        )
        XCTAssertEqual(seekingState.snapshot.progress, 6)
        XCTAssertEqual(
            seekingState.snapshot.bufferedDuration,
            0
        )
        XCTAssertEqual(seekingNotificationCount, 0)

        let errorState = IRFFDecoderRuntimeState()
        XCTAssertNotNil(
            errorState.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: IRFFAudioFrame(),
                    position: 11,
                    duration: 0.25,
                    size: 16
                )
            }
        )
        XCTAssertTrue(
            errorState.commitDecodeError(
                NSError(
                    domain: "audio-error",
                    code: 1
                ),
                generation: 0,
                notification: {}
            )
        )
        var errorNotificationCount = 0
        XCTAssertFalse(
            errorState.commitPendingAudioProgress(
                generation: 0,
                playbackDuration: 30,
                notification: { _ in
                    errorNotificationCount += 1
                }
            )
        )
        XCTAssertFalse(
            errorState.commitBufferedDuration(
                5,
                playbackDuration: 30,
                generation: 0,
                currentTime: 100,
                notification: { _ in
                    errorNotificationCount += 1
                }
            )
        )
        XCTAssertEqual(errorState.snapshot.progress, 0)
        XCTAssertEqual(
            errorState.snapshot.bufferedDuration,
            0
        )
        XCTAssertEqual(errorNotificationCount, 0)

        let renderErrorState =
            IRFFDecoderRuntimeState()
        XCTAssertTrue(
            renderErrorState.commitDecodeError(
                NSError(
                    domain: "render-error",
                    code: 2
                ),
                generation: 0,
                notification: {}
            )
        )
        var dequeueCount = 0
        let queuedFrame = IRFFAudioFrame()
        XCTAssertNil(
            renderErrorState.tryFetchAudioFrame {
                _ in
                dequeueCount += 1
                return IRFFAudioFrameTransfer(
                    frame: queuedFrame,
                    position: 1,
                    duration: 0.25,
                    size: 16
                )
            }
        )
        XCTAssertEqual(dequeueCount, 0)
        XCTAssertNil(
            renderErrorState.currentAudioFrame
        )
    }

    func testAudioRetirementCapacityMatchesPoolAndRecoversFromBackpressure() {
        XCTAssertEqual(
            IRFFFramePool.audioMaximumCapacity,
            500
        )
        let state = IRFFDecoderRuntimeState()

        for index in
                0..<IRFFFramePool
                    .audioMaximumCapacity {
            let frame = IRFFAudioFrame()
            let lease = state.tryFetchAudioFrame {
                _ in
                IRFFAudioFrameTransfer(
                    frame: frame,
                    position: TimeInterval(index),
                    duration: 0.01,
                    size: 2
                )
            }
            XCTAssertTrue(lease?.frame === frame)
            XCTAssertTrue(
                state.tryFinishAudioFrame(
                    ObjectIdentifier(frame)
                )
            )
        }

        let blockedFrame = IRFFAudioFrame()
        XCTAssertTrue(
            state.tryFetchAudioFrame { _ in
                IRFFAudioFrameTransfer(
                    frame: blockedFrame,
                    position: 500,
                    duration: 0.01,
                    size: 2
                )
            }?.frame === blockedFrame
        )
        XCTAssertFalse(
            state.tryFinishAudioFrame(
                ObjectIdentifier(blockedFrame)
            ),
            "A full preallocated retirement buffer must apply backpressure"
        )
        XCTAssertTrue(
            state.currentAudioFrame === blockedFrame
        )

        XCTAssertNotNil(
            state.takeFinishedAudioFrame()
        )
        XCTAssertTrue(
            state.tryFinishAudioFrame(
                ObjectIdentifier(blockedFrame)
            ),
            "Retirement must recover immediately after the monitor releases one slot"
        )
        XCTAssertNil(state.currentAudioFrame)

        var retiredCount = 1
        while state.takeFinishedAudioFrame()
                != nil {
            retiredCount += 1
        }
        XCTAssertEqual(
            retiredCount,
            IRFFFramePool
                .audioMaximumCapacity + 1
        )
    }

    func testConcurrentSnapshotsAndMutationsRemainValid() {
        let state = IRFFDecoderRuntimeState()
        let failures = LockedFailureCount()

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            if index.isMultiple(of: 2) {
                _ = state.setProgress(TimeInterval(index))
                _ = state.setBufferedDuration(TimeInterval(index / 2))
                _ = state.setPaused(index.isMultiple(of: 4))
            } else {
                let snapshot = state.snapshot
                if !snapshot.progress.isFinite ||
                    !snapshot.bufferedDuration.isFinite ||
                    snapshot.progress < 0 ||
                    snapshot.bufferedDuration < 0 {
                    failures.increment()
                }
            }
        }

        XCTAssertEqual(failures.value, 0)
    }
}

private final class LockedFailureCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
