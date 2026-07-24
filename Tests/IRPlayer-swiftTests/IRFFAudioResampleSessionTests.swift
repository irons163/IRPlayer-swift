import IRFFMpeg
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFAudioResampleSessionTests:
    XCTestCase
{
    func testInvalidSetupDoesNotAllocateContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        var setup = makeSetup()
        setup = IRFFAudioResampleSetup(
            outputSamplingRate: 0,
            outputChannelCount:
                setup.outputChannelCount,
            inputSamplingRate:
                setup.inputSamplingRate,
            inputChannelLayout:
                setup.inputChannelLayout,
            inputSampleFormat:
                setup.inputSampleFormat
        )

        XCTAssertNil(
            IRFFAudioResampleSession(
                setup: setup,
                runtime: makeRuntime(events: events)
            )
        )
        XCTAssertTrue(events.value.isEmpty)
    }

    func testAllocationFailureFreesPartialContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let runtime = makeRuntime(
            events: events,
            creationResult: -7
        )

        XCTAssertNil(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: runtime
            )
        )
        XCTAssertEqual(
            events.value,
            ["create", "free"]
        )
    }

    func testInitializationFailureFreesContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let runtime = makeRuntime(
            events: events,
            initializationResult: -8
        )

        XCTAssertNil(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: runtime
            )
        )
        XCTAssertEqual(
            events.value,
            ["create", "initialize", "free"]
        )
    }

    func testConversionGrowsAndReusesManagedSamples() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(events: events)
            )
        )
        XCTAssertTrue(session.matches(makeSetup()))
        var changedSetup = makeSetup()
        changedSetup = IRFFAudioResampleSetup(
            outputSamplingRate: 44_100,
            outputChannelCount:
                changedSetup.outputChannelCount,
            inputSamplingRate:
                changedSetup.inputSamplingRate,
            inputChannelLayout:
                changedSetup.inputChannelLayout,
            inputSampleFormat:
                changedSetup.inputSampleFormat
        )
        XCTAssertFalse(session.matches(changedSetup))
        var frame = AVFrame()
        frame.nb_samples = 4
        var firstSamples: [Int16] = []

        let firstOutcome =
            withUnsafeMutablePointer(to: &frame) {
                framePointer in
                session.withConvertedSamples(
                    from: framePointer,
                    outputFrameCapacity: 4
                ) { samples, _ in
                    firstSamples = Array(samples)
                    return true
                }
            }

        XCTAssertEqual(
            firstOutcome,
            .converted(
                frameCount: 4,
                sampleCount: 8
            )
        )
        XCTAssertEqual(
            firstSamples,
            [1, 2, 3, 4, 5, 6, 7, 8]
        )
        XCTAssertEqual(
            session.diagnostics.sampleCapacity,
            8
        )

        _ = withUnsafeMutablePointer(to: &frame) {
            session.withConvertedSamples(
                from: $0,
                outputFrameCapacity: 2
            ) { _, _ in true }
        }
        XCTAssertEqual(
            session.diagnostics.sampleCapacity,
            8
        )

        _ = withUnsafeMutablePointer(to: &frame) {
            session.withConvertedSamples(
                from: $0,
                outputFrameCapacity: 8
            ) { _, _ in true }
        }
        XCTAssertEqual(
            session.diagnostics.sampleCapacity,
            16
        )
        XCTAssertEqual(
            events.value.filter { $0 == "create" }.count,
            1
        )
    }

    func testConfigurationDistinguishesLayoutsWithSameChannelCount() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(events: events)
            )
        )
        var nativeLayout = AVChannelLayout()
        nativeLayout.order = AV_CHANNEL_ORDER_NATIVE
        nativeLayout.nb_channels = 2
        nativeLayout.u.mask = 0b11

        XCTAssertFalse(
            session.matches(
                makeSetup(
                    inputChannelLayout: nativeLayout
                )
            )
        )
    }

    func testConversionReportsBufferAndFFmpegErrors() throws {
        let bufferEvents =
            LockedDecoderResourceValue<[String]>([])
        let bufferSession = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(
                    events: bufferEvents,
                    outputBufferSize: -9
                )
            )
        )
        var frame = AVFrame()
        frame.nb_samples = 4

        let bufferOutcome =
            withUnsafeMutablePointer(to: &frame) {
                bufferSession.withConvertedSamples(
                    from: $0,
                    outputFrameCapacity: 4
                ) { _, _ in true }
            }
        XCTAssertEqual(
            bufferOutcome,
            .ffmpegError(-9)
        )

        let convertEvents =
            LockedDecoderResourceValue<[String]>([])
        let convertSession = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(
                    events: convertEvents,
                    conversionResult: -10
                )
            )
        )
        let convertOutcome =
            withUnsafeMutablePointer(to: &frame) {
                convertSession.withConvertedSamples(
                    from: $0,
                    outputFrameCapacity: 4
                ) { _, _ in true }
            }
        XCTAssertEqual(
            convertOutcome,
            .ffmpegError(-10)
        )
    }

    func testConversionRejectsInvalidCountsAndConsumer() throws {
        let invalidEvents =
            LockedDecoderResourceValue<[String]>([])
        let invalidSession = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(
                    events: invalidEvents,
                    conversionResult: 5
                )
            )
        )
        var frame = AVFrame()
        frame.nb_samples = 4
        let invalidOutcome =
            withUnsafeMutablePointer(to: &frame) {
                invalidSession.withConvertedSamples(
                    from: $0,
                    outputFrameCapacity: 4
                ) { _, _ in true }
            }
        XCTAssertEqual(
            invalidOutcome,
            .invalidInput
        )

        let rejectedEvents =
            LockedDecoderResourceValue<[String]>([])
        let rejectedSession = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(
                    events: rejectedEvents
                )
            )
        )
        let rejectedOutcome =
            withUnsafeMutablePointer(to: &frame) {
                rejectedSession.withConvertedSamples(
                    from: $0,
                    outputFrameCapacity: 4
                ) { _, _ in false }
            }
        XCTAssertEqual(
            rejectedOutcome,
            .consumerRejected
        )
    }

    func testCloseReleasesContextAndManagedSamplesOnce() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(events: events)
            )
        )
        var frame = AVFrame()
        frame.nb_samples = 4
        _ = withUnsafeMutablePointer(to: &frame) {
            session.withConvertedSamples(
                from: $0,
                outputFrameCapacity: 4
            ) { _, _ in true }
        }

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        XCTAssertFalse(session.matches(makeSetup()))
        XCTAssertEqual(
            session.diagnostics,
            .init(
                closed: true,
                hasContext: false,
                sampleCapacity: 0
            )
        )
        let closedOutcome =
            withUnsafeMutablePointer(to: &frame) {
                session.withConvertedSamples(
                    from: $0,
                    outputFrameCapacity: 4
                ) { _, _ in true }
            }
        XCTAssertEqual(closedOutcome, .closed)
        XCTAssertEqual(
            events.value.filter { $0 == "free" }.count,
            1
        )
    }

    func testCloseWaitsForConversionBorrow() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let conversionStarted =
            DispatchSemaphore(value: 0)
        let releaseConversion =
            DispatchSemaphore(value: 0)
        let runtime = makeRuntime(
            events: events,
            onConvert: {
                conversionStarted.signal()
                releaseConversion.wait()
            }
        )
        let session = try XCTUnwrap(
            IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: runtime
            )
        )
        let conversionFinished =
            DispatchSemaphore(value: 0)
        let closeFinished =
            DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let frame = UnsafeMutablePointer<AVFrame>
                .allocate(capacity: 1)
            frame.initialize(to: AVFrame())
            frame.pointee.nb_samples = 4
            _ = session.withConvertedSamples(
                from: frame,
                outputFrameCapacity: 4
            ) { _, _ in true }
            frame.deinitialize(count: 1)
            frame.deallocate()
            conversionFinished.signal()
        }
        XCTAssertEqual(
            conversionStarted.wait(
                timeout: .now() + 1
            ),
            .success
        )

        DispatchQueue.global().async {
            session.close()
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(
                timeout: .now() + 0.05
            ),
            .timedOut
        )

        releaseConversion.signal()
        XCTAssertEqual(
            conversionFinished.wait(
                timeout: .now() + 1
            ),
            .success
        )
        XCTAssertEqual(
            closeFinished.wait(
                timeout: .now() + 1
            ),
            .success
        )
        XCTAssertEqual(
            events.value.filter { $0 == "free" }.count,
            1
        )
    }

    func testDeinitFreesContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])

        autoreleasepool {
            _ = IRFFAudioResampleSession(
                setup: makeSetup(),
                runtime: makeRuntime(events: events)
            )
        }

        XCTAssertEqual(
            events.value,
            ["create", "initialize", "free"]
        )
    }

    private func makeSetup(
        inputChannelLayout:
            AVChannelLayout? = nil
    )
        -> IRFFAudioResampleSetup
    {
        var layout =
            inputChannelLayout
            ?? AVChannelLayout()
        if inputChannelLayout == nil {
            layout.nb_channels = 2
        }
        return IRFFAudioResampleSetup(
            outputSamplingRate: 48_000,
            outputChannelCount: 2,
            inputSamplingRate: 48_000,
            inputChannelLayout: layout,
            inputSampleFormat: AV_SAMPLE_FMT_S16
        )
    }

    private func makeRuntime(
        events:
            LockedDecoderResourceValue<[String]>,
        creationResult: Int32 = 0,
        initializationResult: Int32 = 0,
        outputBufferSize: Int32? = nil,
        conversionResult: Int32? = nil,
        onConvert: (() -> Void)? = nil
    ) -> IRFFAudioResampleRuntime {
        IRFFAudioResampleRuntime(
            createContext: { _ in
                events.withValue {
                    $0.append("create")
                }
                return IRFFAudioResampleContextCreation(
                    result: creationResult,
                    context: OpaquePointer(
                        bitPattern: 0x1000
                    )
                )
            },
            initializeContext: { _ in
                events.withValue {
                    $0.append("initialize")
                }
                return initializationResult
            },
            outputBufferSize: {
                channelCount,
                frameCapacity in
                if let outputBufferSize {
                    return outputBufferSize
                }
                return channelCount
                    * frameCapacity
                    * Int32(
                        MemoryLayout<Int16>.stride
                    )
            },
            convert: {
                _,
                output,
                outputFrameCapacity,
                _,
                _ in
                events.withValue {
                    $0.append("convert")
                }
                onConvert?()
                let frameCount =
                    conversionResult
                    ?? outputFrameCapacity
                guard frameCount > 0 else {
                    return frameCount
                }
                let writableFrameCount = min(
                    frameCount,
                    outputFrameCapacity
                )
                let sampleCount =
                    Int(writableFrameCount) * 2
                let samples =
                    UnsafeMutableRawPointer(output)
                    .assumingMemoryBound(
                        to: Int16.self
                    )
                for index in 0..<sampleCount {
                    samples[index] = Int16(index + 1)
                }
                return frameCount
            },
            freeContext: { context in
                events.withValue {
                    $0.append("free")
                }
                context = nil
            }
        )
    }
}
