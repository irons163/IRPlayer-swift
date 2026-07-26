import IRFFMpeg
import IRPlayerObjc
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFAudioDecoderTests: XCTestCase {

    func testSampleElementCountRejectsEmptyInputs() {
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 0, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 4, channelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: -1, channelCount: 2))
        XCTAssertEqual(IRFFAudioDecoder.sampleElementCount(numberOfFrames: 3, channelCount: 2), 6)
    }

    func testSampleElementCountRejectsOverflow() {
        XCTAssertNil(IRFFAudioDecoder.sampleElementCount(numberOfFrames: Int.max, channelCount: 2))
    }

    func testSampleByteCountRejectsInvalidAndOverflowingElementCounts() {
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: 0))
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: -1))
        XCTAssertNil(IRFFAudioDecoder.sampleByteCount(numberOfElements: Int.max))
    }

    func testSampleByteCountCalculatesFloatStorageSize() {
        XCTAssertEqual(IRFFAudioDecoder.sampleByteCount(numberOfElements: 3), 12)
    }

    func testFallbackDurationRejectsInvalidAudioOutputInfo() {
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 0, channelCount: 2, samplingRate: 48_000))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 0, samplingRate: 48_000))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 2, samplingRate: 0))
        XCTAssertNil(IRFFAudioDecoder.fallbackDuration(sampleByteCount: 128, channelCount: 2, samplingRate: .infinity))
    }

    func testFallbackDurationCalculatesSecondsFromSampleBytes() throws {
        let duration = try XCTUnwrap(
            IRFFAudioDecoder.fallbackDuration(sampleByteCount: 384_000, channelCount: 2, samplingRate: 48_000)
        )

        XCTAssertEqual(duration, 1, accuracy: 0.0001)
    }

    func testFallbackDurationRejectsDerivedBytesPerSecondOverflow() {
        XCTAssertNil(
            IRFFAudioDecoder.fallbackDuration(
                sampleByteCount: 128,
                channelCount: .max,
                samplingRate: .greatestFiniteMagnitude
            )
        )
    }

    func testSWROutputInfoRejectsInvalidAudioInfo() {
        XCTAssertNil(IRFFAudioDecoder.swrOutputInfo(samplingRate: 0, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.swrOutputInfo(samplingRate: .nan, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.swrOutputInfo(samplingRate: Float64(Int32.max) + 1, channelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.swrOutputInfo(samplingRate: 48_000, channelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.swrOutputInfo(samplingRate: 48_000, channelCount: UInt32(Int32.max) + 1))
    }

    func testSWROutputInfoConvertsValidAudioInfo() throws {
        let info = try XCTUnwrap(IRFFAudioDecoder.swrOutputInfo(samplingRate: 48_000.9, channelCount: 2))

        XCTAssertEqual(info.samplingRate, 48_000)
        XCTAssertEqual(info.channelCount, 2)
    }

    func testSWRInputInfoRejectsMissingOrInvalidCodecContext() {
        XCTAssertNil(IRFFAudioDecoder.swrInputInfo(from: nil))

        var codecContext = AVCodecContext()
        codecContext.sample_rate = 48_000
        codecContext.ch_layout.nb_channels = 2
        codecContext.sample_fmt = AV_SAMPLE_FMT_NONE
        withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            XCTAssertNil(IRFFAudioDecoder.swrInputInfo(from: contextPointer))

            contextPointer.pointee.sample_fmt = AV_SAMPLE_FMT_S16
            contextPointer.pointee.sample_rate = 0
            XCTAssertNil(IRFFAudioDecoder.swrInputInfo(from: contextPointer))

            contextPointer.pointee.sample_rate = 48_000
            contextPointer.pointee.ch_layout = AVChannelLayout()
            XCTAssertNil(IRFFAudioDecoder.swrInputInfo(from: contextPointer))
        }
    }

    func testSWRInputInfoConvertsValidCodecContext() throws {
        var codecContext = AVCodecContext()
        codecContext.sample_rate = 48_000
        codecContext.ch_layout.nb_channels = 2
        codecContext.sample_fmt = AV_SAMPLE_FMT_S16

        let info = try withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            try XCTUnwrap(IRFFAudioDecoder.swrInputInfo(from: contextPointer))
        }

        XCTAssertEqual(info.samplingRate, 48_000)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertEqual(info.sampleFormat, AV_SAMPLE_FMT_S16)
    }

    func testDecodedFrameDurationUsesFiniteTickDuration() {
        let duration = IRFFAudioDecoder.decodedFrameDuration(ticks: 480, timebase: 0.001, fallbackDuration: 1)

        XCTAssertEqual(duration, 0.48, accuracy: 0.0001)
    }

    func testDecodedFrameDurationFallsBackWhenTicksAreMissing() {
        let duration = IRFFAudioDecoder.decodedFrameDuration(ticks: 0, timebase: 0.001, fallbackDuration: 0.25)

        XCTAssertEqual(duration, 0.25, accuracy: 0.0001)
    }

    func testDecodedFrameDurationRejectsInvalidTimingValues() {
        XCTAssertEqual(IRFFAudioDecoder.decodedFrameDuration(ticks: 480, timebase: .infinity, fallbackDuration: 0.25), 0.25)
        XCTAssertEqual(IRFFAudioDecoder.decodedFrameDuration(ticks: -480, timebase: 0.001, fallbackDuration: 0.25), 0.25)
        XCTAssertEqual(IRFFAudioDecoder.decodedFrameDuration(ticks: 0, timebase: 0.001, fallbackDuration: .nan), 0)
        XCTAssertEqual(IRFFAudioDecoder.decodedFrameDuration(ticks: 0, timebase: 0.001, fallbackDuration: nil), 0)
    }

    func testDecodedFrameDurationFallsBackAfterDerivedOverflow() {
        XCTAssertEqual(
            IRFFAudioDecoder.decodedFrameDuration(
                ticks: .max,
                timebase: .greatestFiniteMagnitude,
                fallbackDuration: 0.25
            ),
            0.25
        )
    }

    func testResampleRatioRejectsInvalidAudioInfo() {
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 0, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: .infinity, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 0, outputChannelCount: 2, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 0, inputChannelCount: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 0))
        XCTAssertNil(IRFFAudioDecoder.resampleRatio(outputSamplingRate: Float64(Int.max), inputSamplingRate: 1, outputChannelCount: 2, inputChannelCount: 2))
    }

    func testResampleRatioClampsUpsamplingFactors() {
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 24_000, inputSamplingRate: 48_000, outputChannelCount: 1, inputChannelCount: 2),
            2
        )
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 24_000, outputChannelCount: 4, inputChannelCount: 2),
            8
        )
    }

    func testResampleRatioRoundsUpFractionalChannelExpansion() {
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 48_000, inputSamplingRate: 48_000, outputChannelCount: 3, inputChannelCount: 2),
            4
        )
    }

    func testResampleRatioRoundsUpFractionalSamplingExpansion() {
        XCTAssertEqual(
            IRFFAudioDecoder.resampleRatio(outputSamplingRate: 72_000, inputSamplingRate: 48_000, outputChannelCount: 2, inputChannelCount: 2),
            4
        )
    }

    func testResampleFrameCapacityRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 0, ratio: 2))
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 1024, ratio: 0))
        XCTAssertNil(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: Int32.max, ratio: 2))
    }

    func testResampleFrameCapacityCalculatesInt32Capacity() {
        XCTAssertEqual(IRFFAudioDecoder.resampleFrameCapacity(inputFrameCount: 1024, ratio: 2), 2048)
    }

    func testPacketDecodeResultTreatsRecoverableFFmpegResultsAsNonFailures() {
        XCTAssertFalse(IRFFAudioDecoder.packetDecodeResultIsFailure(0))
        XCTAssertFalse(IRFFAudioDecoder.packetDecodeResultIsFailure(AVERROR(EAGAIN)))
        XCTAssertFalse(
            IRFFAudioDecoder.packetDecodeResultIsFailure(
                IR_AVERROR_EOF
            )
        )
        XCTAssertTrue(IRFFAudioDecoder.packetDecodeResultIsFailure(-1))
    }

    func testShouldDecodePacketRequiresPacketData() {
        XCTAssertFalse(IRFFAudioDecoder.shouldDecodePacket(hasData: false))
        XCTAssertTrue(IRFFAudioDecoder.shouldDecodePacket(hasData: true))
    }

    func testShouldDecodeFrameRequiresFrameAndPrimaryData() {
        XCTAssertFalse(IRFFAudioDecoder.shouldDecodeFrame(hasFrame: false, hasPrimaryData: true))
        XCTAssertFalse(IRFFAudioDecoder.shouldDecodeFrame(hasFrame: true, hasPrimaryData: false))
        XCTAssertTrue(IRFFAudioDecoder.shouldDecodeFrame(hasFrame: true, hasPrimaryData: true))
    }

    func testDirectOutputSampleFormatRequiresS16() {
        XCTAssertTrue(IRFFAudioDecoder.canUseDirectOutput(sampleFormat: AV_SAMPLE_FMT_S16))
        XCTAssertFalse(IRFFAudioDecoder.canUseDirectOutput(sampleFormat: AV_SAMPLE_FMT_FLT))
        XCTAssertFalse(IRFFAudioDecoder.canUseDirectOutput(sampleFormat: AV_SAMPLE_FMT_NONE))
    }

    func testPacketAdmissionDefersWithoutSendingOrClosingPacketAndRecoversAfterSlotRelease() throws {
        let pool = IRFFFramePool(
            capacity: 16,
            frameClassName: IRFFAudioFrame.self
        ) {
            IRFFAudioFrame()
        }
        var heldFrames: [IRFFFrame] = try (0..<9).map { _ in
            try XCTUnwrap(pool.leaseFrame())
        }
        var codecContext = AVCodecContext()
        let delegate = AudioDecoderDelegateSpy(
            samplingRate: 48_000,
            channelCount: 2
        )

        withUnsafeMutablePointer(to: &codecContext) {
            codecContextPointer in
            let decoder = IRFFAudioDecoder(
                codecContext: codecContextPointer,
                timebase: 0.001,
                delegate: delegate,
                framePool: pool,
                packetAdmissionHeadroom: 8
            )
            defer { decoder.destroy() }

            XCTAssertEqual(
                decoder.decodeAdmission.capacity
                    .availableCredits,
                7
            )
            XCTAssertFalse(
                decoder.hasPacketAdmissionCapacity
            )

            var byte: UInt8 = 1
            withUnsafeMutablePointer(to: &byte) {
                bytePointer in
                let packet = IRFFPacket(
                    runtime: IRFFPacketRuntime(
                        moveReference: {
                            destination,
                            source in
                            destination = source
                            source = AVPacket()
                        },
                        unreference: { packet in
                            packet = AVPacket()
                        }
                    )
                )
                XCTAssertEqual(
                    packet.fill { rawPacket in
                        rawPacket.data = bytePointer
                        rawPacket.size = 1
                        return 0
                    },
                    0
                )

                XCTAssertEqual(
                    decoder.putPacket(
                        packet,
                        generation: 0
                    ),
                    .deferred
                )
                XCTAssertEqual(
                    packet.diagnostics.phase,
                    .ready
                )
                XCTAssertTrue(
                    packet.diagnostics.hasData
                )

                heldFrames.removeLast().cancel()
                XCTAssertEqual(
                    decoder.decodeAdmission.capacity
                        .availableCredits,
                    8
                )
                XCTAssertFalse(
                    decoder.hasPacketAdmissionCapacity
                )
                heldFrames.removeLast().cancel()
                XCTAssertEqual(
                    decoder.decodeAdmission.capacity
                        .availableCredits,
                    9
                )
                XCTAssertTrue(
                    decoder.hasPacketAdmissionCapacity
                )

                XCTAssertTrue(packet.close())
            }

            decoder.destroy()
            XCTAssertEqual(
                decoder.decodeAdmission.capacity.phase,
                .closed
            )
            XCTAssertFalse(
                decoder.hasPacketAdmissionCapacity
            )
        }

        heldFrames.forEach { $0.cancel() }
    }

    func testPacketAdmissionAlwaysDerivesCapacityFromTheBackingPool() throws {
        let pool = IRFFFramePool(
            capacity: 4,
            frameClassName: IRFFAudioFrame.self
        ) {
            IRFFAudioFrame()
        }
        let heldFrames: [IRFFFrame] = try (0..<4).map {
            _ in
            try XCTUnwrap(pool.leaseFrame())
        }
        var codecContext = AVCodecContext()
        withUnsafeMutablePointer(to: &codecContext) {
            codecContextPointer in
            let decoder = IRFFAudioDecoder(
                codecContext: codecContextPointer,
                timebase: 0.001,
                delegate: AudioDecoderDelegateSpy(
                    samplingRate: 48_000,
                    channelCount: 2
                ),
                framePool: pool,
                packetAdmissionHeadroom: Int.max
            )
            defer { decoder.destroy() }

            let admission =
                decoder.decodeAdmission.capacity
            XCTAssertEqual(
                admission.limits.frameCapacity,
                4
            )
            XCTAssertEqual(
                admission.limits.packetHeadroom,
                4
            )
            XCTAssertEqual(
                admission.availableCredits,
                0
            )
            XCTAssertFalse(admission.canResumeOutput)
            XCTAssertFalse(admission.canAdmitPacket)
        }
        heldFrames.forEach { $0.cancel() }
    }

    func testInstanceQueueLifecycleAndInvalidPacketRemainCallable() {
        var codecContext = AVCodecContext()
        let delegate = AudioDecoderDelegateSpy(samplingRate: 48_000, channelCount: 2)

        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let decoder = IRFFAudioDecoder.decoder(
                codecContext: codecContextPointer,
                timebase: 0.001,
                delegate: delegate
            )

            XCTAssertEqual(decoder.size(), 0)
            XCTAssertTrue(decoder.isEmpty())
            XCTAssertEqual(decoder.duration(), 0)

            let packet = IRFFPacket()
            XCTAssertEqual(
                decoder.putPacket(packet),
                .consumed(.needsInput)
            )
            XCTAssertEqual(
                packet.diagnostics.phase,
                .closed
            )

            XCTAssertEqual(decoder.size(), 0)
            XCTAssertTrue(decoder.isEmpty())
            XCTAssertEqual(decoder.duration(), 0)

            decoder.destroy()
            decoder.destroy()

            XCTAssertNil(decoder.waitForFrame())
            XCTAssertNil(decoder.dequeueFrame())
        }

        XCTAssertGreaterThanOrEqual(delegate.samplingRateRequestCount, 1)
        XCTAssertGreaterThanOrEqual(delegate.channelCountRequestCount, 1)
    }

    func testPutPacketDecodesGeneratedPCM16AudioFrame() throws {
        let url = try makeTinyPCM16WAVFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(contentURL: url, videoFormat: .mpeg4)
        addTeardownBlock {
            context.destroy()
        }
        context.setupSync()

        XCTAssertNil(context.error)
        XCTAssertTrue(context.audioEnable)
        XCTAssertFalse(context.audioTracks.isEmpty)
        XCTAssertNotNil(context.audioCodecContext)

        let codecContext = try XCTUnwrap(context.audioCodecContext)
        let delegate = AudioDecoderDelegateSpy(samplingRate: 48_000, channelCount: 2)
        let decoder = IRFFAudioDecoder.decoder(
            codecContext: codecContext,
            timebase: context.audioTimebase,
            delegate: delegate
        )

        var decodedFrame: IRFFAudioFrame?
        let audioTrackIndex = try XCTUnwrap(context.audioTrack?.index)
        for _ in 0..<32 where decodedFrame == nil {
            var rawPacket = AVPacket()
            guard context.readFrame(&rawPacket) >= 0 else {
                break
            }
            let packet = IRFFPacket(
                consuming: &rawPacket
            )
            guard let streamIndex =
                    packet.snapshot?.streamIndex,
                  Int(streamIndex)
                    == audioTrackIndex else {
                continue
            }

            XCTAssertEqual(
                decoder.putPacket(packet),
                .consumed(.needsInput)
            )
            XCTAssertEqual(
                packet.diagnostics.phase,
                .closed
            )
            if !decoder.isEmpty() {
                decodedFrame = decoder.dequeueFrame()
            }
        }

        let frame = try XCTUnwrap(decodedFrame)
        XCTAssertGreaterThan(frame.duration, 0)
        XCTAssertGreaterThan(frame.size, 0)
        let samples = try XCTUnwrap(frame.sampleSnapshot())
        XCTAssertEqual(
            samples.count * MemoryLayout<Float>.stride,
            frame.size
        )
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertTrue(samples.contains { $0 != 0 })
        XCTAssertTrue(
            samples.allSatisfy {
                (-1.0...1.0).contains($0)
            }
        )
        XCTAssertEqual(decoder.size(), 0)

        decoder.flush()
        XCTAssertTrue(decoder.isEmpty())
    }

    func testInvalidateWaitsForLastAdmittedEnqueueThenFlushesTheStaleFrame() throws {
        let url = try makeTinyPCM16WAVFile()
        addTeardownBlock {
            try? FileManager.default
                .removeItem(at: url)
        }
        let context = IRFFFormatContext(
            contentURL: url,
            videoFormat: .mpeg4
        )
        addTeardownBlock {
            context.destroy()
        }
        context.setupSync()
        let codecContext = try XCTUnwrap(
            context.audioCodecContext
        )
        let audioTrackIndex = try XCTUnwrap(
            context.audioTrack?.index
        )

        let reachedLastEnqueueWindow =
            DispatchSemaphore(value: 0)
        let releaseLastEnqueue =
            DispatchSemaphore(value: 0)
        let publishedInvalidation =
            DispatchSemaphore(value: 0)
        let pool = IRFFFramePool(
            capacity: 4,
            frameClassName: IRFFAudioFrame.self
        ) {
            IRFFAudioFrame()
        }
        let decoder = IRFFAudioDecoder(
            codecContext: codecContext,
            timebase: context.audioTimebase,
            delegate: AudioDecoderDelegateSpy(
                samplingRate: 48_000,
                channelCount: 2
            ),
            framePool: pool,
            packetAdmissionHeadroom: 1,
            hooks: IRFFAudioDecoderHooks(
                willEnqueueFrame: {
                    reachedLastEnqueueWindow.signal()
                    releaseLastEnqueue.wait()
                },
                didPublishInvalidation: {
                    generation in
                    if generation == 1 {
                        publishedInvalidation.signal()
                    }
                }
            )
        )
        addTeardownBlock {
            releaseLastEnqueue.signal()
            decoder.destroy()
        }

        var packetToDecode: IRFFPacket?
        for _ in 0..<32
            where packetToDecode == nil {
            var rawPacket = AVPacket()
            guard context.readFrame(&rawPacket) >= 0 else {
                break
            }
            let packet = IRFFPacket(
                consuming: &rawPacket
            )
            if packet.snapshot?.streamIndex ==
                Int32(audioTrackIndex) {
                packetToDecode = packet
            } else {
                packet.close()
            }
        }
        let packet = try XCTUnwrap(packetToDecode)
        let packetResult =
            LockedDecoderResourceValue<
                IRFFAudioPacketDecodeResult?
            >(nil)
        let packetFinished =
            DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let result = decoder.putPacket(
                packet,
                generation: 0
            )
            packetResult.withValue {
                $0 = result
            }
            packetFinished.signal()
        }
        XCTAssertEqual(
            reachedLastEnqueueWindow.wait(
                timeout: .now() + 2
            ),
            .success
        )

        let invalidateResult =
            LockedDecoderResourceValue<
                Bool?
            >(nil)
        let invalidateFinished =
            DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let result = decoder.invalidate(
                generation: 1
            )
            invalidateResult.withValue {
                $0 = result
            }
            invalidateFinished.signal()
        }
        XCTAssertEqual(
            publishedInvalidation.wait(
                timeout: .now() + 2
            ),
            .success
        )
        XCTAssertEqual(
            invalidateFinished.wait(
                timeout: .now() + 0.05
            ),
            .timedOut
        )

        releaseLastEnqueue.signal()
        XCTAssertEqual(
            packetFinished.wait(
                timeout: .now() + 2
            ),
            .success
        )
        XCTAssertEqual(
            invalidateFinished.wait(
                timeout: .now() + 2
            ),
            .success
        )

        XCTAssertEqual(
            packetResult.value,
            .consumed(.canceled)
        )
        XCTAssertEqual(
            invalidateResult.value,
            true
        )
        XCTAssertEqual(
            packet.diagnostics.phase,
            .closed
        )
        XCTAssertTrue(decoder.isEmpty())
        XCTAssertEqual(
            pool.diagnostics.leasedCount,
            0
        )
    }

    func testLongAudioBackpressureMatchesUnboundedDecodeWithoutDroppingOutput() throws {
        let inputFrameCount = 131_072
        let url = try makeAudioAdmissionWAVFile(
            frameCount: inputFrameCount
        )
        addTeardownBlock {
            try? FileManager.default
                .removeItem(at: url)
        }
        let baseline =
            try decodeAudioAdmissionFixture(
                at: url,
                poolCapacity: 500,
                packetHeadroom: 8
            )
        let bounded =
            try decodeAudioAdmissionFixture(
                at: url,
                poolCapacity: 4,
                packetHeadroom: 2
            )

        XCTAssertEqual(
            baseline.audioPacketCount,
            baseline.acceptedPacketCount
        )
        XCTAssertEqual(
            bounded.audioPacketCount,
            bounded.acceptedPacketCount
        )
        XCTAssertEqual(
            bounded.audioPacketCount,
            baseline.audioPacketCount
        )
        XCTAssertEqual(
            baseline.acceptedPacketCount,
            baseline.packetCloseVerificationCount
        )
        XCTAssertEqual(
            bounded.acceptedPacketCount,
            bounded.packetCloseVerificationCount
        )
        XCTAssertEqual(
            bounded.decodedFrameCount,
            baseline.decodedFrameCount
        )
        XCTAssertEqual(
            bounded.decodedSampleCount,
            baseline.decodedSampleCount
        )
        XCTAssertEqual(
            bounded.decodedSampleCount,
            inputFrameCount * 2
        )
        XCTAssertEqual(
            bounded.decodedDuration,
            baseline.decodedDuration,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            bounded.decodedDuration,
            Double(inputFrameCount) / 48_000,
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(
            bounded.deferredSubmissionCount,
            0
        )
        XCTAssertGreaterThan(
            bounded.backpressureReleaseCount,
            0
        )
        XCTAssertEqual(
            baseline.endingLeasedCount,
            0
        )
        XCTAssertEqual(
            baseline.endingPlayingCount,
            0
        )
        XCTAssertEqual(bounded.endingLeasedCount, 0)
        XCTAssertEqual(bounded.endingPlayingCount, 0)
        XCTAssertLessThanOrEqual(
            bounded.maximumPoolCount,
            4
        )
    }
}

private final class AudioDecoderDelegateSpy: IRFFAudioDecoderDelegate {
    private let samplingRate: Float64
    private let channelCount: UInt32
    private(set) var samplingRateRequestCount = 0
    private(set) var channelCountRequestCount = 0

    init(samplingRate: Float64, channelCount: UInt32) {
        self.samplingRate = samplingRate
        self.channelCount = channelCount
    }

    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64) {
        samplingRateRequestCount += 1
        samplingRate = self.samplingRate
    }

    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32) {
        channelCountRequestCount += 1
        channelCount = self.channelCount
    }
}

private struct AudioAdmissionDecodeStatistics {
    var audioPacketCount = 0
    var acceptedPacketCount = 0
    var packetCloseVerificationCount = 0
    var deferredSubmissionCount = 0
    var backpressureReleaseCount = 0
    var decodedFrameCount = 0
    var decodedSampleCount = 0
    var decodedDuration: TimeInterval = 0
    var maximumPoolCount = 0
    var endingLeasedCount = 0
    var endingPlayingCount = 0
}

private enum AudioAdmissionFixtureError:
    Error
{
    case invalidContext
    case unexpectedReadResult(Int32)
    case unexpectedPumpResult(
        IRFFAudioCodecPumpResult
    )
    case missingBackpressureFrame
    case missingSamples
    case retryLimitExceeded
}

private func decodeAudioAdmissionFixture(
    at url: URL,
    poolCapacity: Int,
    packetHeadroom: Int
) throws -> AudioAdmissionDecodeStatistics {
    let context = IRFFFormatContext(
        contentURL: url,
        videoFormat: .mpeg4
    )
    defer { context.destroy() }
    context.setupSync()
    guard context.error == nil,
          let codecContext =
            context.audioCodecContext,
          let audioTrackIndex =
            context.audioTrack?.index else {
        throw AudioAdmissionFixtureError
            .invalidContext
    }

    let pool = IRFFFramePool(
        capacity: poolCapacity,
        frameClassName: IRFFAudioFrame.self
    ) {
        IRFFAudioFrame()
    }
    let decoder = IRFFAudioDecoder(
        codecContext: codecContext,
        timebase: context.audioTimebase,
        delegate: AudioDecoderDelegateSpy(
            samplingRate: 48_000,
            channelCount: 2
        ),
        framePool: pool,
        packetAdmissionHeadroom:
            packetHeadroom
    )
    defer { decoder.destroy() }

    var statistics =
        AudioAdmissionDecodeStatistics()
    var pendingPacket: IRFFPacket?
    var reachedEndOfInput = false
    var iterationCount = 0
    let maximumIterationCount = 100_000

    func consumeOneFrame() throws {
        guard let transfer =
                decoder.tryDequeueFrame() else {
            throw AudioAdmissionFixtureError
                .missingBackpressureFrame
        }
        defer { transfer.frame.cancel() }
        guard let samples =
                transfer.frame.sampleSnapshot() else {
            throw AudioAdmissionFixtureError
                .missingSamples
        }
        statistics.decodedFrameCount += 1
        statistics.decodedSampleCount +=
            samples.count
        statistics.decodedDuration +=
            transfer.duration
        statistics.backpressureReleaseCount += 1
    }

    func recordConsumedPacket(
        _ packet: IRFFPacket,
        result: IRFFAudioCodecPumpResult
    ) throws {
        switch result {
        case .needsInput,
             .backpressured:
            break
        case .endOfStream,
             .canceled,
             .failed:
            throw AudioAdmissionFixtureError
                .unexpectedPumpResult(result)
        }
        statistics.acceptedPacketCount += 1
        guard packet.diagnostics.phase ==
                .closed,
              !packet.close() else {
            throw AudioAdmissionFixtureError
                .unexpectedPumpResult(.failed(-1))
        }
        statistics
            .packetCloseVerificationCount += 1
    }

    while !reachedEndOfInput ||
            pendingPacket != nil {
        iterationCount += 1
        guard iterationCount <=
                maximumIterationCount else {
            throw AudioAdmissionFixtureError
                .retryLimitExceeded
        }

        if let packet = pendingPacket {
            let resumeResult =
                decoder.resumePendingOutput(
                    generation: 0
                )
            switch resumeResult {
            case .needsInput:
                break
            case .backpressured:
                try consumeOneFrame()
                continue
            case .endOfStream,
                 .canceled,
                 .failed:
                throw AudioAdmissionFixtureError
                    .unexpectedPumpResult(
                        resumeResult
                    )
            }
            guard decoder
                    .hasPacketAdmissionCapacity else {
                try consumeOneFrame()
                continue
            }

            switch decoder.putPacket(
                packet,
                generation: 0
            ) {
            case let .consumed(result):
                try recordConsumedPacket(
                    packet,
                    result: result
                )
                pendingPacket = nil
            case .deferred:
                statistics
                    .deferredSubmissionCount += 1
                guard packet.diagnostics.phase ==
                        .ready else {
                    throw AudioAdmissionFixtureError
                        .unexpectedPumpResult(
                            .failed(-1)
                        )
                }
                try consumeOneFrame()
            }
            continue
        }

        guard !reachedEndOfInput else {
            break
        }
        var rawPacket = AVPacket()
        let readResult =
            context.readFrame(&rawPacket)
        if readResult == AVERROR(EAGAIN) {
            continue
        }
        if readResult == IR_AVERROR_EOF {
            reachedEndOfInput = true
            continue
        }
        guard readResult >= 0 else {
            throw AudioAdmissionFixtureError
                .unexpectedReadResult(readResult)
        }

        let packet = IRFFPacket(
            consuming: &rawPacket
        )
        guard packet.snapshot?.streamIndex ==
                Int32(audioTrackIndex) else {
            packet.close()
            continue
        }
        statistics.audioPacketCount += 1

        switch decoder.putPacket(
            packet,
            generation: 0
        ) {
        case let .consumed(result):
            try recordConsumedPacket(
                packet,
                result: result
            )
        case .deferred:
            statistics
                .deferredSubmissionCount += 1
            guard packet.diagnostics.phase ==
                    .ready else {
                throw AudioAdmissionFixtureError
                    .unexpectedPumpResult(
                        .failed(-1)
                    )
            }
            pendingPacket = packet
        }
        statistics.maximumPoolCount = max(
            statistics.maximumPoolCount,
            pool.diagnostics.totalCount
        )
    }

    var drainIterationCount = 0
    drainLoop: while true {
        drainIterationCount += 1
        guard drainIterationCount <=
                maximumIterationCount else {
            throw AudioAdmissionFixtureError
                .retryLimitExceeded
        }
        let result = decoder.drain(
            generation: 0
        )
        switch result {
        case .endOfStream:
            break drainLoop
        case .backpressured:
            try consumeOneFrame()
        case .needsInput,
             .canceled,
             .failed:
            throw AudioAdmissionFixtureError
                .unexpectedPumpResult(result)
        }
    }

    while !decoder.isEmpty() {
        try consumeOneFrame()
    }
    let endingPool = pool.diagnostics
    statistics.maximumPoolCount = max(
        statistics.maximumPoolCount,
        endingPool.totalCount
    )
    statistics.endingLeasedCount =
        endingPool.leasedCount
    statistics.endingPlayingCount =
        endingPool.playingCount
    return statistics
}

private func makeAudioAdmissionWAVFile(
    frameCount: Int
) throws -> URL {
    let url = URL(
        fileURLWithPath: NSTemporaryDirectory()
    ).appendingPathComponent(
        "irff-audio-admission-\(UUID().uuidString).wav"
    )
    let channelCount: UInt16 = 2
    let sampleRate: UInt32 = 48_000
    let bitsPerSample: UInt16 = 16
    let blockAlign =
        channelCount * bitsPerSample / 8
    let byteRate =
        sampleRate * UInt32(blockAlign)
    var samples = Data()
    samples.reserveCapacity(
        max(0, frameCount) * Int(blockAlign)
    )
    for index in 0..<max(0, frameCount) {
        let left = Int16(
            truncatingIfNeeded: index * 31
        )
        samples.appendAudioAdmissionLittleEndian(
            left
        )
        samples.appendAudioAdmissionLittleEndian(
            0 &- left
        )
    }

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendAudioAdmissionLittleEndian(
        UInt32(36 + samples.count)
    )
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendAudioAdmissionLittleEndian(
        UInt32(16)
    )
    data.appendAudioAdmissionLittleEndian(
        UInt16(1)
    )
    data.appendAudioAdmissionLittleEndian(
        channelCount
    )
    data.appendAudioAdmissionLittleEndian(
        sampleRate
    )
    data.appendAudioAdmissionLittleEndian(
        byteRate
    )
    data.appendAudioAdmissionLittleEndian(
        blockAlign
    )
    data.appendAudioAdmissionLittleEndian(
        bitsPerSample
    )
    data.append(contentsOf: "data".utf8)
    data.appendAudioAdmissionLittleEndian(
        UInt32(samples.count)
    )
    data.append(samples)
    try data.write(to: url, options: .atomic)
    return url
}

private extension Data {
    mutating func appendAudioAdmissionLittleEndian<
        Value: FixedWidthInteger
    >(
        _ value: Value
    ) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(
            of: &littleEndianValue
        ) { bytes in
            append(contentsOf: bytes)
        }
    }
}
