import IRFFMpeg
import IRPlayerObjc
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFVideoDecoderTests: XCTestCase {

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

    func testFrameDurationRejectsDerivedOverflow() {
        XCTAssertEqual(
            IRFFVideoDecoder.frameDuration(
                ticks: .max,
                repeatPicture: .max,
                timebase: .greatestFiniteMagnitude,
                fps: 30
            ),
            0
        )
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

    func testPacketDecodeResultTreatsRecoverableFFmpegResultsAsNonFailures() {
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(0))
        XCTAssertFalse(IRFFVideoDecoder.packetDecodeResultIsFailure(AVERROR(EAGAIN)))
        XCTAssertFalse(
            IRFFVideoDecoder.packetDecodeResultIsFailure(
                IR_AVERROR_EOF
            )
        )
        XCTAssertTrue(IRFFVideoDecoder.packetDecodeResultIsFailure(-1))
    }

    func testVideoToolBoxRoutingNeverFallsBackAfterHardwareConsumesInput() {
        XCTAssertEqual(
            IRFFVideoDecoder
                .videoToolBoxTransition(
                    backend: .undecided,
                    result: .notAvailable
                ),
            .init(
                backend: .ffmpeg,
                route: .fallbackToFFmpeg
            )
        )
        XCTAssertEqual(
            IRFFVideoDecoder
                .videoToolBoxTransition(
                    backend: .undecided,
                    result: .accepted
                ),
            .init(
                backend: .videoToolBox,
                route: .consume
            )
        )
        XCTAssertEqual(
            IRFFVideoDecoder
                .videoToolBoxTransition(
                    backend: .videoToolBox,
                    result: .notAvailable
                ),
            .init(
                backend: .videoToolBox,
                route: .fail
            )
        )
        XCTAssertEqual(
            IRFFVideoDecoder
                .videoToolBoxTransition(
                    backend: .videoToolBox,
                    result: .failed
                ),
            .init(
                backend: .videoToolBox,
                route: .fail
            )
        )
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
                                                         timebase: 0.25,
                                                         fps: 25),
            0.04,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 4,
                                                         packetSize: 32,
                                                         timebase: 0.25,
                                                         fps: 25),
            0
        )
        XCTAssertEqual(
            IRFFVideoDecoder.packetQueueFallbackDuration(packetDuration: 0,
                                                         packetSize: 0,
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
            XCTAssertNil(decoder.dequeueFrame())

            decoder.send(videoFrame: frame)

            XCTAssertFalse(decoder.empty())
            XCTAssertFalse(decoder.frameEmpty())
            XCTAssertEqual(decoder.frameDuration(), 0.5)
            XCTAssertTrue(decoder.dequeueFrame() === frame)
            XCTAssertTrue(decoder.frameEmpty())

            var rawPacket = AVPacket()
            rawPacket.duration = 4
            rawPacket.size = 32
            let packet = IRFFPacket(
                consuming: &rawPacket
            )

            decoder.putPacket(packet)

            XCTAssertFalse(decoder.packetEmpty())
            XCTAssertEqual(decoder.packetSize(), 32)
            XCTAssertEqual(decoder.packetDuration(), 1, accuracy: 0.0001)

            decoder.flush()

            XCTAssertFalse(decoder.packetEmpty())
            XCTAssertEqual(decoder.packetSize(), 0)
            XCTAssertEqual(decoder.packetDuration(), 0)
            XCTAssertEqual(
                packet.diagnostics.phase,
                .closed
            )

            decoder.destroy()

            XCTAssertTrue(decoder.packetEmpty())
            XCTAssertTrue(decoder.frameEmpty())
            XCTAssertNil(decoder.dequeueFrame())
            XCTAssertNil(decoder.waitForFrame())
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

            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            decoder.decodeFrameThread()

            XCTAssertFalse(decoder.decoding)
        }

        XCTAssertEqual(delegate.bufferingCheckCallCount, 1)
        XCTAssertEqual(delegate.bufferedDurationUpdateCallCount, 0)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testDestroyRejectsAndCancelsLateExternalFrame() {
        var codecContext = AVCodecContext()
        let frame = IRFFVideoFrame()
        let probe = VideoFrameLifecycleProbe()
        frame.delegate = probe

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )

            decoder.destroy()
            decoder.destroy()
            decoder.send(videoFrame: frame)

            XCTAssertTrue(decoder.frameEmpty())
            XCTAssertNil(decoder.dequeueFrame())
        }

        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testExternalFrameAdmissionIsBoundedNonBlockingAndReclaimsRejection() {
        var codecContext = AVCodecContext()
        let framePool = IRFFFramePool(
            capacity: 1,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        )
        let rejectedFrame = IRFFVideoFrame()
        let probe = VideoFrameLifecycleProbe()
        rejectedFrame.delegate = probe

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: framePool,
                packetAdmissionHeadroom: 0,
                maximumQueuedPacketCount: 1
            )
            let admittedFrame =
                IRFFVideoFrame()

            XCTAssertTrue(
                decoder.trySend(
                    videoFrame: admittedFrame
                )
            )
            XCTAssertFalse(
                decoder.trySend(
                    videoFrame: rejectedFrame
                )
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                1
            )
            XCTAssertTrue(
                decoder.dequeueFrame()
                    === admittedFrame
            )
            decoder.destroy()
        }

        XCTAssertEqual(probe.cancelCount, 1)
    }

    func testSameGenerationFlushInvalidatesStaleEndOfStreamCommitTicket() {
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            let commitReady =
                DispatchSemaphore(value: 0)
            let releaseCommit =
                DispatchSemaphore(value: 0)
            let commitFinished =
                DispatchSemaphore(value: 0)
            let committed =
                LockedVideoDecoderValue(false)
            let drainCalled =
                LockedVideoDecoderValue(false)

            DispatchQueue.global().async {
                committed.value =
                    decoder
                        .drainAndCommitEndOfStream(
                            generation: 0,
                            transitionRevision: 0,
                            beforeCommit: {
                                commitReady
                                    .signal()
                                releaseCommit
                                    .wait()
                            }
                        ) {
                            drainCalled.value =
                                true
                        }
                commitFinished.signal()
            }

            XCTAssertEqual(
                commitReady.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            XCTAssertTrue(
                decoder.invalidate(
                    generation: 0
                )
            )
            releaseCommit.signal()
            XCTAssertEqual(
                commitFinished.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            XCTAssertFalse(committed.value)
            XCTAssertFalse(drainCalled.value)

            let replacement = IRFFVideoFrame()
            decoder.send(
                videoFrame: replacement
            )
            XCTAssertTrue(
                decoder.dequeueFrame()
                    === replacement
            )
            decoder.destroy()
        }
    }

    func testSeekGenerationRejectsStaleVideoFailureAndCallback() {
        var codecContext = AVCodecContext()
        let delegate = VideoDecoderDelegateSpy()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            XCTAssertTrue(
                decoder.invalidate(
                    generation: 1
                )
            )

            XCTAssertFalse(
                decoder.commitDecodingError(
                    NSError(
                        domain: "stale-video",
                        code: 7
                    ),
                    generation: 0
                )
            )
            XCTAssertNil(decoder.error)
            XCTAssertTrue(
                delegate.errors.isEmpty
            )
            decoder.destroy()
        }
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

            var rawPacket = AVPacket()
            rawPacket.stream_index = 0
            rawPacket.duration = 1
            rawPacket.size = 1
            var byte: UInt8 = 1
            withUnsafeMutablePointer(to: &byte) { pointer in
                rawPacket.data = pointer
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                decoder.putPacket(packet)
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                decoder.decodeFrameThread()
                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .closed
                )
            }

            XCTAssertFalse(decoder.decoding)
            XCTAssertTrue(decoder.dequeueFrame() === sourceFrame)
            XCTAssertTrue(decoder.frameEmpty())
        }

        XCTAssertEqual(source.shouldHandleCallCount, 1)
        XCTAssertEqual(source.decodeFrameCallCount, 1)
        XCTAssertEqual(source.mismatchedCallbackCount, 0)
        XCTAssertEqual(source.lastPacket?.data, Data([1]))
        XCTAssertEqual(source.lastDescriptor?.payloadByteCount, 1)
        XCTAssertEqual(source.lastDescriptor?.sideDataCount, 0)
        XCTAssertEqual(source.lastInfo?.timebase, 0.25)
        XCTAssertEqual(source.lastInfo?.framesPerSecond, 30)
        XCTAssertEqual(delegate.bufferedDurationUpdateCallCount, 1)
        XCTAssertEqual(delegate.bufferingCheckCallCount, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testAcceptedCustomPacketCopyFailureIsTerminalWithoutBuiltinFallback() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let delegate = VideoDecoderDelegateSpy()
        let source = VideoDecoderDataSourceSpy(
            shouldHandle: true,
            frame: IRFFVideoFrame()
        )
        let packetRuntime = IRFFPacketRuntime(
            moveReference: {
                destination,
                source in
                destination = source
                source = AVPacket()
            },
            unreference: { _ in }
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            decoder.source = source
            decoder.videoToolBoxEnable = false
            var payload: UInt8 = 7
            var malformedSideData =
                AVPacketSideData()
            malformedSideData.size = 1
            malformedSideData.data = nil

            withUnsafeMutablePointer(
                to: &payload
            ) { payloadPointer in
                withUnsafeMutablePointer(
                    to: &malformedSideData
                ) { sideDataPointer in
                    var rawPacket = AVPacket()
                    rawPacket.data =
                        payloadPointer
                    rawPacket.size = 1
                    rawPacket.stream_index = 0
                    rawPacket.side_data =
                        sideDataPointer
                    rawPacket.side_data_elems = 1
                    let packet = IRFFPacket(
                        consuming: &rawPacket,
                        runtime: packetRuntime
                    )

                    XCTAssertEqual(
                        decoder.putPacket(packet),
                        .accepted
                    )
                    XCTAssertTrue(
                        decoder.finish(
                            generation: 0
                        )
                    )
                    decoder.decodeFrameThread()

                    XCTAssertEqual(
                        packet.diagnostics.phase,
                        .closed
                    )
                }
            }

            XCTAssertNotNil(decoder.error)
            XCTAssertTrue(decoder.frameEmpty())
            decoder.destroy()
        }

        XCTAssertEqual(
            source.shouldHandleCallCount,
            1
        )
        XCTAssertEqual(
            source.decodeFrameCallCount,
            0
        )
        XCTAssertEqual(delegate.errors.count, 1)
    }

    func testAsyncCustomSourceOwnsValuesAfterInternalPacketClose() {
        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_H264
        codecContext.width = 2
        codecContext.height = 2
        let outputFrame = IRFFVideoFrame()
        outputFrame.duration = 0.25
        let delivered = expectation(
            description: "async custom frame delivered"
        )
        let source = AsyncVideoInput(
            outputFrame: outputFrame,
            onDelivered: {
                delivered.fulfill()
            }
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            source.videoOutput = decoder
            decoder.source = source
            codecContextPointer.pointee.codec_id =
                AV_CODEC_ID_MPEG4
            codecContextPointer.pointee.width = 99
            codecContextPointer.pointee.height = 99
            var byte: UInt8 = 7

            withUnsafeMutablePointer(to: &byte) {
                bytePointer in
                var rawPacket = AVPacket()
                rawPacket.data = bytePointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                rawPacket.pts = 4
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )

                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                let decodeFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    decodeFinished.signal()
                }

                let closeDeadline =
                    Date().addingTimeInterval(2)
                while packet.diagnostics.phase
                        != .closed,
                      Date() < closeDeadline {
                    Thread.sleep(
                        forTimeInterval: 0.002
                    )
                }

                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .closed
                )
                XCTAssertEqual(
                    decodeFinished.wait(
                        timeout:
                            .now() + 0.05
                    ),
                    .timedOut
                )

                bytePointer.pointee = 99
                source.releaseAsyncDecode()
                wait(
                    for: [delivered],
                    timeout: 2
                )
                XCTAssertEqual(
                    decodeFinished.wait(
                        timeout:
                            .now() + 2
                    ),
                    .success
                )
            }

            XCTAssertEqual(
                source.capturedPacket?.data,
                Data([7])
            )
            XCTAssertEqual(
                source.capturedInfo?.codec.identifier,
                .h264
            )
            XCTAssertEqual(
                source.capturedInfo?.codec.width,
                2
            )
            XCTAssertTrue(
                decoder.dequeueFrame() === outputFrame
            )
            decoder.destroy()
        }
    }

    func testExplicitCustomDropReleasesReservationBeforeEndOfStream() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source = VideoDecoderDataSourceSpy(
            shouldHandle: true,
            frame: nil
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                decoder.decodeFrameThread()
                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .closed
                )
            }
            XCTAssertTrue(decoder.empty())
            XCTAssertNil(decoder.error)
            decoder.destroy()
        }
    }

    func testUnretainedDeferredCompletionAutoDropsAndCannotHangEOF() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source =
            UnretainedDeferredVideoSource()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                decoder.decodeFrameThread()
            }
            XCTAssertEqual(
                source.decodeCallCount,
                1
            )
            XCTAssertTrue(decoder.empty())
            decoder.destroy()
        }
    }

    func testActiveWorkerRejectsSameGenerationFlushBeforeCustomRegistration() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source =
            DeferredCompletionVideoSource(
                blocksRouting: true
            )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                let workerFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    workerFinished.signal()
                }

                XCTAssertTrue(
                    source.waitUntilRouting(
                        timeout: 1
                    )
                )
                XCTAssertFalse(decoder.flush())
                source.releaseRouting()
                XCTAssertTrue(
                    source.waitUntilDeferred(
                        timeout: 1
                    )
                )
                XCTAssertTrue(
                    source.drop()
                )
                XCTAssertEqual(
                    workerFinished.wait(
                        timeout:
                            .now() + 2
                    ),
                    .success
                )
            }
            XCTAssertNil(decoder.error)
            decoder.destroy()
        }
    }

    func testDestroyUnblocksDeferredEOFAndLateFrameIsReclaimed() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source =
            DeferredCompletionVideoSource()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                let workerFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    workerFinished.signal()
                }
                XCTAssertTrue(
                    source.waitUntilDeferred(
                        timeout: 1
                    )
                )

                decoder.destroy()
                XCTAssertEqual(
                    workerFinished.wait(
                        timeout:
                            .now() + 2
                    ),
                    .success
                )
            }

            let lateFrame =
                IRFFVideoFrame()
            let probe =
                VideoFrameLifecycleProbe()
            lateFrame.delegate = probe
            XCTAssertFalse(
                source.send(
                    lateFrame
                )
            )
            XCTAssertEqual(probe.cancelCount, 1)
        }
    }

    func testDeferredCompletionAdmitsFirstFrameAndReclaimsDuplicate() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source =
            DeferredCompletionVideoSource()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                let workerFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    workerFinished.signal()
                }
                XCTAssertTrue(
                    source.waitUntilDeferred(
                        timeout: 1
                    )
                )

                let firstFrame =
                    IRFFVideoFrame()
                XCTAssertTrue(
                    source.send(firstFrame)
                )
                XCTAssertEqual(
                    workerFinished.wait(
                        timeout:
                            .now() + 2
                    ),
                    .success
                )
                XCTAssertTrue(
                    decoder.dequeueFrame()
                        === firstFrame
                )
            }

            let duplicateFrame =
                IRFFVideoFrame()
            let probe =
                VideoFrameLifecycleProbe()
            duplicateFrame.delegate = probe
            XCTAssertFalse(
                source.send(
                    duplicateFrame
                )
            )
            XCTAssertEqual(probe.cancelCount, 1)
            decoder.destroy()
        }
    }

    func testNewGenerationInvalidationCancelsBlockedEOSCapacityWait() throws {
        var codecContext = AVCodecContext()
        let backpressured =
            DispatchSemaphore(value: 0)
        let framePool = IRFFFramePool(
            capacity: 1,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        let heldFrame = try XCTUnwrap(
            framePool.leaseFrame()
                as? IRFFAVYUVVideoFrame
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: framePool,
                softwareFrameBackpressureObserver: {
                    backpressured.signal()
                }
            )
            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            let drainFinished =
                DispatchSemaphore(value: 0)
            let committed =
                LockedVideoDecoderValue(false)
            DispatchQueue.global().async {
                committed.value =
                    decoder
                        .drainAndCommitEndOfStream(
                            generation: 0,
                            transitionRevision: 0
                        ) {
                            decoder
                                .waitForSoftwareFrameLeaseForTesting(
                                    generation: 0
                                )?
                                .cancel()
                        }
                drainFinished.signal()
            }

            XCTAssertEqual(
                backpressured.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            let invalidated =
                LockedVideoDecoderValue(false)
            let invalidateFinished =
                DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                invalidated.value =
                    decoder.invalidate(
                        generation: 1
                    )
                invalidateFinished.signal()
            }
            XCTAssertEqual(
                invalidateFinished.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            XCTAssertTrue(invalidated.value)
            XCTAssertEqual(
                drainFinished.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            XCTAssertFalse(committed.value)

            heldFrame.cancel()
            let replacement =
                IRFFVideoFrame()
            XCTAssertTrue(
                decoder.trySend(
                    videoFrame: replacement
                )
            )
            XCTAssertTrue(
                decoder.dequeueFrame()
                    === replacement
            )
            decoder.destroy()
        }
    }

    func testDestroyCancelsBlockedEOSCapacityWait() throws {
        var codecContext = AVCodecContext()
        let backpressured =
            DispatchSemaphore(value: 0)
        let framePool = IRFFFramePool(
            capacity: 1,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        _ = try XCTUnwrap(
            framePool.leaseFrame()
                as? IRFFAVYUVVideoFrame
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: framePool,
                softwareFrameBackpressureObserver: {
                    backpressured.signal()
                }
            )
            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            let drainFinished =
                DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = decoder
                    .drainAndCommitEndOfStream(
                        generation: 0,
                        transitionRevision: 0
                    ) {
                        decoder
                            .waitForSoftwareFrameLeaseForTesting(
                                generation: 0
                            )?
                            .cancel()
                    }
                drainFinished.signal()
            }
            XCTAssertEqual(
                backpressured.wait(
                    timeout: .now() + 1
                ),
                .success
            )

            let destroyFinished =
                DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                decoder.destroy()
                destroyFinished.signal()
            }
            XCTAssertEqual(
                destroyFinished.wait(
                    timeout: .now() + 1
                ),
                .success
            )
            XCTAssertEqual(
                drainFinished.wait(
                    timeout: .now() + 1
                ),
                .success
            )
        }
    }

    func testCustomFailureCallbackMayDestroyDecoderReentrantlyExactlyOnce() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let delegate =
            ReentrantVideoDecoderDelegate()
        let source =
            FailingVideoDecoderSource()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            decoder.source = source
            var byte: UInt8 = 1
            withUnsafeMutablePointer(
                to: &byte
            ) { pointer in
                var rawPacket = AVPacket()
                rawPacket.data = pointer
                rawPacket.size = 1
                rawPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming: &rawPacket
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .accepted
                )
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )
                decoder.decodeFrameThread()
            }
            XCTAssertEqual(delegate.errorCount, 1)
            XCTAssertFalse(
                decoder.commitDecodingError(
                    NSError(
                        domain: "stale",
                        code: 2
                    ),
                    generation: 0
                )
            )
            XCTAssertEqual(delegate.errorCount, 1)
        }
    }

    func testDeferredFailureWakesEmptyPacketWaitAndRejectsAllLaterAdmission() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let delegate = VideoDecoderDelegateSpy()
        let source =
            CollectingDeferredVideoSource()
        let packetRuntime = IRFFPacketRuntime(
            moveReference: {
                destination,
                source in
                destination = source
                source = AVPacket()
            },
            unreference: { _ in }
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            decoder.source = source
            var payloads: [UInt8] = [1, 2, 3]
            payloads.withUnsafeMutableBufferPointer {
                buffer in
                for index in 0..<2 {
                    var rawPacket = AVPacket()
                    rawPacket.data =
                        buffer.baseAddress?
                            .advanced(
                                by: index
                            )
                    rawPacket.size = 1
                    rawPacket.stream_index = 0
                    rawPacket.pts =
                        Int64(index)
                    XCTAssertEqual(
                        decoder.putPacket(
                            IRFFPacket(
                                consuming:
                                    &rawPacket,
                                runtime:
                                    packetRuntime
                            )
                        ),
                        .accepted
                    )
                }

                let workerFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    workerFinished.signal()
                }
                XCTAssertTrue(
                    source.waitForPendingCount(
                        2,
                        timeout: 1
                    )
                )
                let waitDeadline =
                    Date().addingTimeInterval(1)
                while decoder
                        .packetQueueWaitingConsumerCount ==
                        0,
                      Date() < waitDeadline {
                    Thread.sleep(
                        forTimeInterval: 0.001
                    )
                }
                XCTAssertEqual(
                    decoder
                        .packetQueueWaitingConsumerCount,
                    1
                )

                let terminalError = NSError(
                    domain:
                        "custom-video-terminal",
                    code: 71
                )
                XCTAssertTrue(
                    source.failOldest(
                        terminalError
                    )
                )
                XCTAssertEqual(
                    workerFinished.wait(
                        timeout:
                            .now() + 1
                    ),
                    .success
                )
                XCTAssertEqual(
                    decoder.error,
                    terminalError
                )
                XCTAssertEqual(
                    delegate.errors.count,
                    1
                )

                let lateFrame =
                    IRFFVideoFrame()
                let lateProbe =
                    VideoFrameLifecycleProbe()
                lateFrame.delegate = lateProbe
                XCTAssertFalse(
                    source.sendOldest(
                        lateFrame
                    )
                )
                XCTAssertEqual(
                    lateProbe.cancelCount,
                    1
                )

                let externalFrame =
                    IRFFVideoFrame()
                let externalProbe =
                    VideoFrameLifecycleProbe()
                externalFrame.delegate =
                    externalProbe
                XCTAssertFalse(
                    decoder.trySend(
                        videoFrame:
                            externalFrame
                    )
                )
                XCTAssertEqual(
                    externalProbe.cancelCount,
                    1
                )

                var rejectedPacket =
                    AVPacket()
                rejectedPacket.data =
                    buffer.baseAddress?
                        .advanced(by: 2)
                rejectedPacket.size = 1
                rejectedPacket.stream_index = 0
                let packet = IRFFPacket(
                    consuming:
                        &rejectedPacket,
                    runtime: packetRuntime
                )
                XCTAssertEqual(
                    decoder.putPacket(packet),
                    .rejected
                )
                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .closed
                )
                XCTAssertFalse(
                    decoder.finish(
                        generation: 0
                    )
                )
                XCTAssertFalse(
                    decoder
                        .decodeAdmission
                        .acceptsPackets
                )
                XCTAssertEqual(
                    decoder
                        .decodeAdmission
                        .capacity
                        .phase,
                    .closed
                )
                XCTAssertTrue(decoder.empty())
                XCTAssertFalse(
                    decoder.commitDecodingError(
                        NSError(
                            domain: "stale",
                            code: 72
                        ),
                        generation: 0
                    )
                )
                XCTAssertEqual(
                    delegate.errors.count,
                    1
                )
            }
            decoder.destroy()
        }
    }

    func testQueuedEOFFailureAndDestroyRaceAlwaysUnblocksWorker() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let delegate =
            ConcurrentVideoDecoderDelegateSpy()
        let source =
            CollectingDeferredVideoSource()
        let packetRuntime = IRFFPacketRuntime(
            moveReference: {
                destination,
                source in
                destination = source
                source = AVPacket()
            },
            unreference: { _ in }
        )

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: delegate
            )
            decoder.source = source
            var payloads: [UInt8] = [1, 2]
            payloads.withUnsafeMutableBufferPointer {
                buffer in
                for index in 0..<buffer.count {
                    var rawPacket = AVPacket()
                    rawPacket.data =
                        buffer.baseAddress?
                            .advanced(
                                by: index
                            )
                    rawPacket.size = 1
                    rawPacket.stream_index = 0
                    XCTAssertEqual(
                        decoder.putPacket(
                            IRFFPacket(
                                consuming:
                                    &rawPacket,
                                runtime:
                                    packetRuntime
                            )
                        ),
                        .accepted
                    )
                }
                XCTAssertTrue(
                    decoder.finish(
                        generation: 0
                    )
                )

                let workerFinished =
                    DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    workerFinished.signal()
                }
                XCTAssertTrue(
                    source.waitForPendingCount(
                        2,
                        timeout: 1
                    )
                )

                let raceStart =
                    DispatchSemaphore(value: 0)
                let raceGroup = DispatchGroup()
                let failureAccepted =
                    LockedVideoDecoderValue(false)
                raceGroup.enter()
                DispatchQueue.global().async {
                    raceStart.wait()
                    failureAccepted.value =
                        source.failOldest(
                            NSError(
                                domain:
                                    "custom-video-race",
                                code: 73
                            )
                        )
                    raceGroup.leave()
                }
                raceGroup.enter()
                DispatchQueue.global().async {
                    raceStart.wait()
                    decoder.destroy()
                    raceGroup.leave()
                }
                raceStart.signal()
                raceStart.signal()

                XCTAssertEqual(
                    raceGroup.wait(
                        timeout: .now() + 1
                    ),
                    .success
                )
                XCTAssertEqual(
                    workerFinished.wait(
                        timeout: .now() + 1
                    ),
                    .success
                )
                XCTAssertEqual(
                    delegate.errorCount,
                    failureAccepted.value
                        ? 1
                        : 0
                )

                let lateFrame =
                    IRFFVideoFrame()
                let probe =
                    VideoFrameLifecycleProbe()
                lateFrame.delegate = probe
                XCTAssertFalse(
                    source.sendOldest(
                        lateFrame
                    )
                )
                XCTAssertEqual(
                    probe.cancelCount,
                    1
                )
            }
        }
    }

    func testDeferredCustomReservationsStayBoundedAndRetryExactPackets() {
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2
        let source =
            CollectingDeferredVideoSource()
        let framePool = IRFFFramePool(
            capacity: 4,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        let packetRuntime = IRFFPacketRuntime(
            moveReference: {
                destination,
                source in
                destination = source
                source = AVPacket()
            },
            unreference: { _ in }
        )
        var packets: [IRFFPacket] = []

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext: codecContextPointer,
                timebase: 1.0 / 120,
                fps: 120,
                delegate: nil,
                framePool: framePool,
                packetAdmissionHeadroom: 1,
                maximumQueuedPacketCount: 2
            )
            decoder.source = source
            let workerFinished =
                DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                decoder.decodeFrameThread()
                workerFinished.signal()
            }

            for index in 0..<12 {
                var payload =
                    UInt8(index)
                withUnsafeMutablePointer(
                    to: &payload
                ) { pointer in
                    var rawPacket =
                        AVPacket()
                    rawPacket.data = pointer
                    rawPacket.size = 1
                    rawPacket.stream_index = 0
                    rawPacket.pts =
                        Int64(index)
                    let packet = IRFFPacket(
                        consuming: &rawPacket,
                        runtime: packetRuntime
                    )
                    packets.append(packet)

                    if index >= 3 {
                        XCTAssertEqual(
                            decoder.putPacket(
                                packet
                            ),
                            .deferred
                        )
                        XCTAssertEqual(
                            packet
                                .diagnostics
                                .phase,
                            .ready
                        )
                        XCTAssertLessThanOrEqual(
                            decoder
                                .decodeAdmission
                                .capacity
                                .occupiedFrameCount,
                            4
                        )
                        XCTAssertTrue(
                            source.dropOldest()
                        )
                    }
                    XCTAssertEqual(
                        decoder.putPacket(packet),
                        .accepted
                    )
                    XCTAssertTrue(
                        source
                            .waitForPendingCount(
                                min(
                                    index + 1,
                                    3
                                ),
                                timeout: 1
                            )
                    )
                    XCTAssertLessThanOrEqual(
                        decoder
                            .decodeAdmission
                            .capacity
                            .occupiedFrameCount,
                        4
                    )
                }
            }

            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            source.dropAll()
            XCTAssertEqual(
                workerFinished.wait(
                    timeout: .now() + 2
                ),
                .success
            )
            XCTAssertEqual(
                source.decodeCallCount,
                12
            )
            XCTAssertTrue(
                packets.allSatisfy {
                    $0.diagnostics.phase ==
                        .closed
                }
            )
            decoder.destroy()
        }
    }

    func testRuntimeConfigurationAndFinishSupportConcurrentAccess() {
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
            let allFinishCallsSucceeded =
                LockedVideoDecoderValue(true)

            for worker in 0..<4 {
                workers.enter()
                workQueue.async {
                    for iteration in 0..<1_000 {
                        decoder.paused = (iteration + worker).isMultiple(of: 2)
                        decoder.videoToolBoxEnable = (iteration + worker).isMultiple(of: 5)
                        decoder.maxDecodeDuration = TimeInterval(iteration + 1) / 1_000
                        if iteration.isMultiple(of: 100),
                           !decoder.finish(
                                generation: 0
                           ) {
                            allFinishCallsSucceeded
                                .value = false
                        }
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
            XCTAssertTrue(
                allFinishCallsSucceeded.value
            )
            decoder.paused = false
            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
            XCTAssertTrue(
                decoder.finish(
                    generation: 0
                )
            )
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

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoder,
        didError error: Error,
        generation: UInt64
    ) {
        errors.append(error as NSError)
    }

    func videoDecoderNeedUpdateBufferedDuration(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {
        bufferedDurationUpdateCallCount += 1
    }

    func videoDecoderNeedCheckBufferingStatus(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {
        bufferingCheckCallCount += 1
    }
}

private final class VideoDecoderDataSourceSpy: IRFFVideoDecoderDataSource {
    private let shouldHandleResult: Bool
    private let frame: IRFFVideoFrame?
    private(set) var shouldHandleCallCount = 0
    private(set) var decodeFrameCallCount = 0
    private(set) var mismatchedCallbackCount = 0
    private(set) var lastInfo: IRFFVideoDecoderInfo?
    private(set) var lastPacket: IRFFCompressedVideoPacket?
    private(set) var lastDescriptor: IRFFVideoPacketDescriptor?
    private var pendingInfo: IRFFVideoDecoderInfo?
    private var pendingDescriptor: IRFFVideoPacketDescriptor?

    init(shouldHandle: Bool, frame: IRFFVideoFrame?) {
        self.shouldHandleResult = shouldHandle
        self.frame = frame
    }

    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        shouldHandleCallCount += 1
        pendingInfo = videoDecoder
        pendingDescriptor = packet
        lastInfo = videoDecoder
        lastDescriptor = packet
        if !shouldHandleResult {
            pendingInfo = nil
            pendingDescriptor = nil
        }
        return shouldHandleResult
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        decodeFrameCallCount += 1
        if pendingInfo != videoDecoder
            || pendingDescriptor?.payloadByteCount
                != packet.data.count
            || pendingDescriptor?.sideDataCount
                != packet.sideData.count {
            mismatchedCallbackCount += 1
        }
        pendingInfo = nil
        pendingDescriptor = nil
        lastInfo = videoDecoder
        lastPacket = packet
        if let frame {
            return .frame(frame)
        }
        return .dropped
    }
}

private final class VideoFrameLifecycleProbe:
    NSObject,
    IRFFFrameDelegate
{
    private(set) var cancelCount = 0

    func frameDidStartPlaying(_ frame: IRFFFrame) {}
    func frameDidStopPlaying(_ frame: IRFFFrame) {}

    func frameDidCancel(_ frame: IRFFFrame) {
        cancelCount += 1
    }
}

private final class AsyncVideoInput: IRFFVideoInput {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(
        label: "IRFFVideoDecoderTests.async-input"
    )
    private let outputFrame: IRFFVideoFrame
    private let onDelivered: () -> Void
    private var storedInfo: IRFFVideoDecoderInfo?
    private var storedPacket: IRFFCompressedVideoPacket?

    var capturedInfo: IRFFVideoDecoderInfo? {
        lock.lock()
        defer { lock.unlock() }
        return storedInfo
    }

    var capturedPacket: IRFFCompressedVideoPacket? {
        lock.lock()
        defer { lock.unlock() }
        return storedPacket
    }

    init(
        outputFrame: IRFFVideoFrame,
        onDelivered: @escaping () -> Void
    ) {
        self.outputFrame = outputFrame
        self.onDelivered = onDelivered
        super.init(outputType: .decoder)
    }

    override func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        true
    }

    override func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        queue.async { [weak self] in
            guard let self else { return }
            self.gate.wait()
            self.lock.lock()
            self.storedInfo = videoDecoder
            self.storedPacket = packet
            self.lock.unlock()
            _ = completion.send(
                videoFrame:
                    self.outputFrame
            )
            self.onDelivered()
        }
        return .deferred
    }

    func releaseAsyncDecode() {
        gate.signal()
    }
}

private final class UnretainedDeferredVideoSource:
    IRFFVideoDecoderDataSource
{
    private(set) var decodeCallCount = 0

    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        true
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        decodeCallCount += 1
        return .deferred
    }
}

private final class DeferredCompletionVideoSource:
    IRFFVideoDecoderDataSource
{
    private let lock = NSLock()
    private let routingReached =
        DispatchSemaphore(value: 0)
    private let routingGate =
        DispatchSemaphore(value: 0)
    private let deferredReached =
        DispatchSemaphore(value: 0)
    private let blocksRouting: Bool
    private var storedCompletion:
        IRFFCustomVideoDecodeCompletion?

    init(blocksRouting: Bool = false) {
        self.blocksRouting = blocksRouting
    }

    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        routingReached.signal()
        if blocksRouting {
            routingGate.wait()
        }
        return true
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        lock.lock()
        storedCompletion = completion
        lock.unlock()
        deferredReached.signal()
        return .deferred
    }

    func waitUntilRouting(
        timeout: TimeInterval
    ) -> Bool {
        routingReached.wait(
            timeout: .now() + timeout
        ) == .success
    }

    func releaseRouting() {
        routingGate.signal()
    }

    func waitUntilDeferred(
        timeout: TimeInterval
    ) -> Bool {
        deferredReached.wait(
            timeout: .now() + timeout
        ) == .success
    }

    func send(
        _ frame: IRFFVideoFrame
    ) -> Bool {
        lock.lock()
        let completion =
            storedCompletion
        lock.unlock()
        return completion?.send(
            videoFrame: frame
        ) ?? false
    }

    func drop() -> Bool {
        lock.lock()
        let completion =
            storedCompletion
        lock.unlock()
        return completion?.drop()
            ?? false
    }
}

private final class FailingVideoDecoderSource:
    IRFFVideoDecoderDataSource
{
    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        true
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        .failed(
            NSError(
                domain: "custom-video-test",
                code: 1
            )
        )
    }
}

private final class CollectingDeferredVideoSource:
    IRFFVideoDecoderDataSource
{
    private let condition = NSCondition()
    private var completions:
        [IRFFCustomVideoDecodeCompletion] = []
    private(set) var decodeCallCount = 0

    func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        true
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        condition.lock()
        decodeCallCount += 1
        completions.append(completion)
        condition.broadcast()
        condition.unlock()
        return .deferred
    }

    func waitForPendingCount(
        _ count: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline =
            Date().addingTimeInterval(
                timeout
            )
        condition.lock()
        while completions.count < count {
            guard condition.wait(
                until: deadline
            ) else {
                condition.unlock()
                return false
            }
        }
        condition.unlock()
        return true
    }

    func dropOldest() -> Bool {
        condition.lock()
        guard !completions.isEmpty else {
            condition.unlock()
            return false
        }
        let completion =
            completions.removeFirst()
        condition.unlock()
        return completion.drop()
    }

    func failOldest(
        _ error: Error
    ) -> Bool {
        condition.lock()
        guard !completions.isEmpty else {
            condition.unlock()
            return false
        }
        let completion =
            completions.removeFirst()
        condition.unlock()
        return completion.fail(error)
    }

    func sendOldest(
        _ frame: IRFFVideoFrame
    ) -> Bool {
        condition.lock()
        guard !completions.isEmpty else {
            condition.unlock()
            frame.cancel()
            return false
        }
        let completion =
            completions.removeFirst()
        condition.unlock()
        return completion.send(
            videoFrame: frame
        )
    }

    func dropAll() {
        condition.lock()
        let completions =
            self.completions
        self.completions.removeAll()
        condition.unlock()
        for completion in completions {
            _ = completion.drop()
        }
    }
}

private final class ReentrantVideoDecoderDelegate:
    IRFFVideoDecoderDelegate
{
    private(set) var errorCount = 0

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoder,
        didError error: Error,
        generation: UInt64
    ) {
        errorCount += 1
        videoDecoder.destroy()
    }

    func videoDecoderNeedUpdateBufferedDuration(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {}

    func videoDecoderNeedCheckBufferingStatus(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {}
}

private final class ConcurrentVideoDecoderDelegateSpy:
    IRFFVideoDecoderDelegate
{
    private let lock = NSLock()
    private var storedErrorCount = 0

    var errorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedErrorCount
    }

    func videoDecoder(
        _ videoDecoder: IRFFVideoDecoder,
        didError error: Error,
        generation: UInt64
    ) {
        lock.lock()
        storedErrorCount += 1
        lock.unlock()
    }

    func videoDecoderNeedUpdateBufferedDuration(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {}

    func videoDecoderNeedCheckBufferingStatus(
        _ videoDecoder: IRFFVideoDecoder,
        generation: UInt64
    ) {}
}

private final class LockedVideoDecoderValue<
    Value
>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
