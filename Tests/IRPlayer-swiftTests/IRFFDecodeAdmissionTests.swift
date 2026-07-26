import XCTest
import IRFFMpeg
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFDecodeAdmissionTests:
    XCTestCase
{
    func testLimitsClampInvalidInputsWithoutArithmeticOverflow() {
        let empty = IRFFDecodeAdmission.Limits(
            frameCapacity: Int.min,
            packetHeadroom: Int.max
        )
        XCTAssertEqual(empty.frameCapacity, 0)
        XCTAssertEqual(empty.packetHeadroom, 0)
        XCTAssertEqual(empty.highWatermark, 0)

        let bounded = IRFFDecodeAdmission.Limits(
            frameCapacity: 60,
            packetHeadroom: Int.max
        )
        XCTAssertEqual(
            bounded.packetHeadroom,
            60
        )
        XCTAssertEqual(bounded.highWatermark, 0)
    }

    func testPacketAdmissionPreservesHeadroomAndOneCreditResumesOutput() {
        let limits = IRFFDecodeAdmission.Limits(
            frameCapacity: 500,
            packetHeadroom: 8
        )
        let admit = IRFFDecodeAdmission.Snapshot(
            limits: limits,
            occupiedFrameCount: 491
        )
        XCTAssertEqual(admit.availableCredits, 9)
        XCTAssertEqual(admit.highWatermark, 492)
        XCTAssertTrue(admit.canAdmitPacket)
        XCTAssertTrue(admit.canResumeOutput)
        XCTAssertFalse(admit.shouldThrottlePacketRead)

        let throttle = IRFFDecodeAdmission.Snapshot(
            limits: limits,
            occupiedFrameCount: 492
        )
        XCTAssertEqual(
            throttle.availableCredits,
            8
        )
        XCTAssertFalse(throttle.canAdmitPacket)
        XCTAssertTrue(throttle.canResumeOutput)
        XCTAssertTrue(
            throttle.shouldThrottlePacketRead
        )

        let full = IRFFDecodeAdmission.Snapshot(
            limits: limits,
            occupiedFrameCount: 500
        )
        XCTAssertFalse(full.canAdmitPacket)
        XCTAssertFalse(full.canResumeOutput)
    }

    func testClosedAdmissionHasNoCreditsEvenWhenPoolIsEmpty() {
        let snapshot = IRFFDecodeAdmission.Snapshot(
            limits: IRFFDecodeAdmission.Limits(
                frameCapacity: 500,
                packetHeadroom: 8
            ),
            occupiedFrameCount: 0,
            phase: .closed
        )

        XCTAssertEqual(snapshot.availableCredits, 0)
        XCTAssertFalse(snapshot.canResumeOutput)
        XCTAssertFalse(snapshot.canAdmitPacket)
        XCTAssertTrue(snapshot.shouldThrottlePacketRead)
    }

    func testOneHourAt120FPSRemainsBoundedAndEventuallyAdmitsEveryFrame() {
        let limits = IRFFDecodeAdmission.Limits(
            frameCapacity: 60,
            packetHeadroom: 8
        )
        let targetFrameCount = 120 * 60 * 60
        var producedFrameCount = 0
        var consumedFrameCount = 0
        var occupiedFrameCount = 0
        var maximumOccupiedFrameCount = 0
        var throttleCount = 0
        var stalled = false

        while producedFrameCount < targetFrameCount {
            let admission =
                IRFFDecodeAdmission.Snapshot(
                    limits: limits,
                    occupiedFrameCount:
                        occupiedFrameCount
                )
            if admission.canAdmitPacket {
                occupiedFrameCount += 1
                producedFrameCount += 1
                maximumOccupiedFrameCount = max(
                    maximumOccupiedFrameCount,
                    occupiedFrameCount
                )
            } else {
                guard occupiedFrameCount > 0 else {
                    stalled = true
                    break
                }
                occupiedFrameCount -= 1
                consumedFrameCount += 1
                throttleCount += 1
            }
        }
        consumedFrameCount += occupiedFrameCount
        occupiedFrameCount = 0

        XCTAssertEqual(
            producedFrameCount,
            targetFrameCount
        )
        XCTAssertFalse(stalled)
        XCTAssertEqual(
            consumedFrameCount,
            targetFrameCount
        )
        XCTAssertEqual(occupiedFrameCount, 0)
        XCTAssertGreaterThan(throttleCount, 0)
        XCTAssertLessThanOrEqual(
            maximumOccupiedFrameCount,
            limits.highWatermark
        )
    }

    func testLongAudioMultiFramePacketsThrottleThenRecoverWithoutDroppingOutput() {
        let limits = IRFFDecodeAdmission.Limits(
            frameCapacity: 500,
            packetHeadroom: 8
        )
        let targetPacketCount = 20_000
        var packetIndex = 0
        var occupiedFrameCount = 0
        var producedFrameCount = 0
        var consumedFrameCount = 0
        var expectedFrameCount = 0
        var throttleCount = 0
        var maximumOccupiedFrameCount = 0
        var stalled = false

        while packetIndex < targetPacketCount {
            let outputFrameCount =
                packetIndex % limits.packetHeadroom + 1
            let admission =
                IRFFDecodeAdmission.Snapshot(
                    limits: limits,
                    occupiedFrameCount:
                        occupiedFrameCount
                )
            guard admission.canAdmitPacket else {
                let releaseCount = min(
                    37,
                    occupiedFrameCount
                )
                guard releaseCount > 0 else {
                    stalled = true
                    break
                }
                occupiedFrameCount -= releaseCount
                consumedFrameCount += releaseCount
                throttleCount += 1
                continue
            }

            occupiedFrameCount += outputFrameCount
            producedFrameCount += outputFrameCount
            expectedFrameCount += outputFrameCount
            packetIndex += 1
            maximumOccupiedFrameCount = max(
                maximumOccupiedFrameCount,
                occupiedFrameCount
            )
        }
        consumedFrameCount += occupiedFrameCount

        XCTAssertEqual(packetIndex, targetPacketCount)
        XCTAssertFalse(stalled)
        XCTAssertEqual(
            producedFrameCount,
            expectedFrameCount
        )
        XCTAssertEqual(
            consumedFrameCount,
            expectedFrameCount
        )
        XCTAssertGreaterThan(throttleCount, 0)
        XCTAssertLessThanOrEqual(
            maximumOccupiedFrameCount,
            limits.frameCapacity
        )
    }

    func testVideoMixedPoolAndExternalFramesUseTheExactUnionOfCredits() throws {
        let pool = IRFFFramePool(
            capacity: 4,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        var heldPoolFrames: [IRFFFrame] =
            try (0..<2).map { _ in
                try XCTUnwrap(
                    pool.leaseFrame()
                )
            }
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext:
                    codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: pool,
                packetAdmissionHeadroom: 1
            )
            defer {
                heldPoolFrames.forEach {
                    $0.cancel()
                }
                decoder.destroy()
            }

            let firstExternalFrame =
                IRFFVideoFrame()
            XCTAssertTrue(
                decoder.trySend(
                    videoFrame:
                        firstExternalFrame
                )
            )
            XCTAssertTrue(
                decoder.trySend(
                    videoFrame:
                        IRFFVideoFrame()
                )
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                4
            )

            let rejectedProbe =
                DecodeAdmissionFrameProbe()
            let rejectedFrame =
                IRFFVideoFrame()
            rejectedFrame.delegate =
                rejectedProbe
            XCTAssertFalse(
                decoder.trySend(
                    videoFrame:
                        rejectedFrame
                )
            )
            XCTAssertEqual(
                rejectedProbe.cancelCount,
                1
            )

            guard let dequeuedFrame =
                    decoder.dequeueFrame() else {
                XCTFail(
                    "Expected the first external frame"
                )
                return
            }
            XCTAssertTrue(
                dequeuedFrame ===
                    firstExternalFrame
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                3
            )
            XCTAssertTrue(
                decoder.trySend(
                    videoFrame:
                        dequeuedFrame
                )
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                4
            )

            heldPoolFrames
                .removeLast()
                .cancel()
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                3
            )
            XCTAssertTrue(
                decoder.trySend(
                    videoFrame:
                        IRFFVideoFrame()
                )
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                4
            )
        }
    }

    func testSoftwareLeaseAndExternalAdmissionShareOneLinearizedCredit() {
        let pool = IRFFFramePool(
            capacity: 1,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        let reachedLeaseGate =
            DispatchSemaphore(value: 0)
        let releaseLeaseGate =
            DispatchSemaphore(value: 0)
        let softwareFinished =
            DispatchSemaphore(value: 0)
        let externalStarted =
            DispatchSemaphore(value: 0)
        let externalFinished =
            DispatchSemaphore(value: 0)
        let softwareFrame =
            DecodeAdmissionLockedValue<
                IRFFAVYUVVideoFrame?
            >(nil)
        let externalAccepted =
            DecodeAdmissionLockedValue<
                Bool?
            >(nil)
        var codecContext = AVCodecContext()

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext:
                    codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: pool,
                packetAdmissionHeadroom: 1,
                softwareFrameWillLeaseObserver: {
                    reachedLeaseGate.signal()
                    releaseLeaseGate.wait()
                }
            )
            defer {
                releaseLeaseGate.signal()
                softwareFrame.value?.cancel()
                decoder.destroy()
            }

            DispatchQueue.global().async {
                softwareFrame.value =
                    decoder
                        .waitForSoftwareFrameLeaseForTesting(
                            generation: 0
                        )
                softwareFinished.signal()
            }
            XCTAssertEqual(
                reachedLeaseGate.wait(
                    timeout: .now() + 2
                ),
                .success
            )

            let externalFrame =
                IRFFVideoFrame()
            DispatchQueue.global().async {
                externalStarted.signal()
                externalAccepted.value =
                    decoder.trySend(
                        videoFrame:
                            externalFrame
                    )
                externalFinished.signal()
            }
            XCTAssertEqual(
                externalStarted.wait(
                    timeout: .now() + 2
                ),
                .success
            )
            XCTAssertEqual(
                externalFinished.wait(
                    timeout: .now() + 0.05
                ),
                .timedOut
            )

            releaseLeaseGate.signal()
            XCTAssertEqual(
                softwareFinished.wait(
                    timeout: .now() + 2
                ),
                .success
            )
            XCTAssertEqual(
                externalFinished.wait(
                    timeout: .now() + 2
                ),
                .success
            )
            XCTAssertNotNil(softwareFrame.value)
            XCTAssertEqual(
                externalAccepted.value,
                false
            )
            XCTAssertEqual(
                pool.diagnostics.leasedCount,
                1
            )
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                1
            )

            softwareFrame.value?.cancel()
            softwareFrame.value = nil
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                0
            )
        }
    }

    func testCustomReservationAtomicallyConvertsIntoANonPooledFrameCredit() throws {
        let pool = IRFFFramePool(
            capacity: 4,
            frameClassName:
                IRFFAVYUVVideoFrame.self
        ) {
            IRFFAVYUVVideoFrame()
        }
        let heldPoolFrame =
            try XCTUnwrap(
                pool.leaseFrame()
            )
        let source =
            DeferredDecodeAdmissionSource()
        let decodeFinished =
            DispatchSemaphore(value: 0)
        var codecContext = AVCodecContext()
        codecContext.codec_id =
            AV_CODEC_ID_MPEG4
        codecContext.width = 2
        codecContext.height = 2

        withUnsafeMutablePointer(
            to: &codecContext
        ) { codecContextPointer in
            let decoder = IRFFVideoDecoder(
                codecContext:
                    codecContextPointer,
                timebase: 0.25,
                fps: 30,
                delegate: nil,
                framePool: pool,
                packetAdmissionHeadroom: 1
            )
            decoder.source = source
            defer {
                heldPoolFrame.cancel()
                decoder.destroy()
            }

            XCTAssertTrue(
                decoder.trySend(
                    videoFrame:
                        IRFFVideoFrame()
                )
            )

            var byte: UInt8 = 7
            withUnsafeMutablePointer(
                to: &byte
            ) { bytePointer in
                var rawPacket = AVPacket()
                rawPacket.data = bytePointer
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
                DispatchQueue.global().async {
                    decoder.decodeFrameThread()
                    decodeFinished.signal()
                }

                XCTAssertEqual(
                    source.reachedDecode.wait(
                        timeout: .now() + 2
                    ),
                    .success
                )
                XCTAssertEqual(
                    decoder.decodeAdmission
                        .capacity
                        .occupiedFrameCount,
                    3
                )
                XCTAssertTrue(
                    decoder.trySend(
                        videoFrame:
                            IRFFVideoFrame()
                    )
                )
                XCTAssertEqual(
                    decoder.decodeAdmission
                        .capacity
                        .occupiedFrameCount,
                    4
                )

                let rejectedProbe =
                    DecodeAdmissionFrameProbe()
                let rejectedFrame =
                    IRFFVideoFrame()
                rejectedFrame.delegate =
                    rejectedProbe
                XCTAssertFalse(
                    decoder.trySend(
                        videoFrame:
                            rejectedFrame
                    )
                )
                XCTAssertEqual(
                    rejectedProbe.cancelCount,
                    1
                )

                let completion =
                    try? XCTUnwrap(
                        source.completion
                    )
                XCTAssertTrue(
                    completion?.send(
                        videoFrame:
                            IRFFVideoFrame()
                    ) == true
                )
                XCTAssertEqual(
                    decoder.decodeAdmission
                        .capacity
                        .occupiedFrameCount,
                    4
                )

                let lateProbe =
                    DecodeAdmissionFrameProbe()
                let lateFrame =
                    IRFFVideoFrame()
                lateFrame.delegate =
                    lateProbe
                XCTAssertFalse(
                    completion?.send(
                        videoFrame:
                            lateFrame
                    ) ?? true
                )
                XCTAssertEqual(
                    lateProbe.cancelCount,
                    1
                )

                XCTAssertEqual(
                    decodeFinished.wait(
                        timeout: .now() + 2
                    ),
                    .success
                )
                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .closed
                )
            }

            XCTAssertNotNil(decoder.dequeueFrame())
            XCTAssertNotNil(decoder.dequeueFrame())
            XCTAssertNotNil(decoder.dequeueFrame())
            XCTAssertNil(decoder.dequeueFrame())
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                1
            )
            heldPoolFrame.cancel()
            XCTAssertEqual(
                decoder.decodeAdmission
                    .capacity
                    .occupiedFrameCount,
                0
            )
        }
    }
}

private final class DecodeAdmissionFrameProbe:
    NSObject,
    IRFFFrameDelegate
{
    private(set) var cancelCount = 0

    func frameDidStartPlaying(
        _ frame: IRFFFrame
    ) {}

    func frameDidStopPlaying(
        _ frame: IRFFFrame
    ) {}

    func frameDidCancel(
        _ frame: IRFFFrame
    ) {
        cancelCount += 1
    }
}

private final class DeferredDecodeAdmissionSource:
    IRFFVideoDecoderDataSource
{
    let reachedDecode =
        DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedCompletion:
        IRFFCustomVideoDecodeCompletion?

    var completion:
        IRFFCustomVideoDecodeCompletion?
    {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletion
    }

    func shouldHandle(
        _ videoDecoder:
            IRFFVideoDecoderInfo,
        packet:
            IRFFVideoPacketDescriptor
    ) -> Bool {
        true
    }

    func videoDecoder(
        _ videoDecoder:
            IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        lock.lock()
        storedCompletion = completion
        lock.unlock()
        reachedDecode.signal()
        return .deferred
    }
}

private final class DecodeAdmissionLockedValue<
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
