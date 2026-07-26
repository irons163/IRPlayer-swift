import AVFoundation
import CoreVideo
import Foundation
import IRFFMpeg
import IRPlayerObjc
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRFFFormatContextTests: XCTestCase {

    func testHTTPHeaderSerializationDistinguishesEmptyInput() {
        XCTAssertEqual(
            IRFFFormatContextBuilder
                .serializeHTTPHeaders([:]),
            .empty
        )
    }

    func testHTTPHeaderSerializationIsStableTrimsOWSAndPreservesEmptyValues() {
        XCTAssertEqual(
            IRFFFormatContextBuilder
                .serializeHTTPHeaders([
                    "z-last": "\t final \t",
                    "Authorization": "Bearer token",
                    "X-Empty": " \t"
                ]),
            .serialized(
                "Authorization: Bearer token\r\n"
                    + "X-Empty:\r\n"
                    + "z-last: final\r\n"
            )
        )
    }

    func testHTTPHeaderSerializationRejectsInvalidAndDuplicateNames() {
        let invalidNames = [
            "",
            " Header",
            "Header ",
            "Bad:Name",
            "Bad\nName",
            "Tést"
        ]
        for name in invalidNames {
            XCTAssertEqual(
                IRFFFormatContextBuilder
                    .serializeHTTPHeaders([
                        name: "value"
                    ]),
                .invalid(.invalidName),
                "name must be an exact RFC token"
            )
        }
        XCTAssertEqual(
            IRFFFormatContextBuilder
                .serializeHTTPHeaders([
                    "Host": "one",
                    "host": "two"
                ]),
            .invalid(.duplicateName)
        )
    }

    func testHTTPHeaderSerializationRejectsC0AndDELButAllowsHTABWithinValue() {
        let rejectedValues = [
            "line\rbreak",
            "line\nbreak",
            "nul\u{0000}",
            "control\u{0001}",
            "delete\u{007F}"
        ]
        for value in rejectedValues {
            XCTAssertEqual(
                IRFFFormatContextBuilder
                    .serializeHTTPHeaders([
                        "X-Test": value
                    ]),
                .invalid(.invalidValue)
            )
        }
        XCTAssertEqual(
            IRFFFormatContextBuilder
                .serializeHTTPHeaders([
                    "X-Test": "one\ttwo",
                    "X-Unicode": "台灣"
                ]),
            .serialized(
                "X-Test: one\ttwo\r\n"
                    + "X-Unicode: 台灣\r\n"
            )
        )
    }

    func testHTTPHeaderSerializationEnforcesExactUTF8ByteLimit() {
        let maximum =
            IRFFFormatContextBuilder
                .maximumSerializedHTTPHeaderByteCount
        let exactValue = String(
            repeating: "x",
            count: maximum - 5
        )
        let oversizedValue =
            exactValue + "x"

        guard case let .serialized(value) =
                IRFFFormatContextBuilder
                    .serializeHTTPHeaders([
                        "A": exactValue
                    ]) else {
            return XCTFail(
                "Expected exact boundary to serialize"
            )
        }
        XCTAssertEqual(
            value.utf8.count,
            maximum
        )
        XCTAssertEqual(
            IRFFFormatContextBuilder
                .serializeHTTPHeaders([
                    "A": oversizedValue
                ]),
            .invalid(.sizeLimitExceeded)
        )
    }

    func testInputOptionsWireHeadersAndRTSPTransportIntoOwnedDictionary() throws {
        let options = try XCTUnwrap(
            IRFFFormatContextBuilder
                .makeInputOptions(
                    videoFormat: .rtsp,
                    serializedHTTPHeaders:
                        "X-Test: value\r\n"
                )
        )

        XCTAssertEqual(
            options.values,
            [
                "headers":
                    "X-Test: value\r\n",
                "rtsp_transport": "tcp"
            ]
        )
    }

    func testInvalidHeadersFailBeforeOpeningInputWithoutDisclosingFields() {
        let result =
            IRFFFormatContextBuilder
                .makeGeneration(
                    contentURL: URL(
                        string:
                            "https://example.invalid/stream"
                    )!,
                    videoFormat: .mpeg4,
                    contentHeaders: [
                        "Secret\nHeader":
                            "private-value"
                    ],
                    interruptState:
                        IRFFFormatContextInterruptState()
                )

        guard case let .failure(error) =
                result else {
            return XCTFail(
                "Expected invalid configuration failure"
            )
        }
        XCTAssertEqual(
            error.code,
            IRFFDecoderErrorCode
                .formatInvalidHeaders
                .rawValue
        )
        XCTAssertFalse(
            error.description.contains(
                "Secret"
            )
        )
        XCTAssertFalse(
            error.description.contains(
                "private-value"
            )
        )
    }

    func testStreamLookupRejectsMissingContextStreamsAndOutOfRangeIndex() {
        XCTAssertNil(IRFFFormatContext.stream(at: 0, in: nil))

        var formatContext = AVFormatContext()
        formatContext.nb_streams = 1
        formatContext.streams = nil

        withUnsafeMutablePointer(to: &formatContext) { contextPointer in
            XCTAssertNil(IRFFFormatContext.stream(at: -1, in: contextPointer))
            XCTAssertNil(IRFFFormatContext.stream(at: 0, in: contextPointer))
            XCTAssertNil(IRFFFormatContext.stream(at: 1, in: contextPointer))
        }
    }

    func testStreamLookupReturnsExistingStream() {
        var formatContext = AVFormatContext()
        var stream = AVStream()

        withUnsafeMutablePointer(to: &stream) { streamPointer in
            var streams: [UnsafeMutablePointer<AVStream>?] = [streamPointer]

            streams.withUnsafeMutableBufferPointer { streamBuffer in
                formatContext.nb_streams = 1
                formatContext.streams = streamBuffer.baseAddress

                withUnsafeMutablePointer(to: &formatContext) { contextPointer in
                    XCTAssertEqual(IRFFFormatContext.stream(at: 0, in: contextPointer), streamPointer)
                }
            }
        }
    }

    func testDecoderLookupRejectsMissingAndInvalidCodecContext() {
        XCTAssertNil(IRFFFormatContext.decoder(for: nil))

        var codecContext = AVCodecContext()
        codecContext.codec_id = AV_CODEC_ID_NONE

        withUnsafeMutablePointer(to: &codecContext) { contextPointer in
            XCTAssertNil(IRFFFormatContext.decoder(for: contextPointer))
        }
    }

    func testDictionaryOptionApplicationRequiresNonNegativeResult() {
        XCTAssertTrue(IRFFFormatContext.dictionaryOptionWasApplied(0))
        XCTAssertTrue(IRFFFormatContext.dictionaryOptionWasApplied(1))
        XCTAssertFalse(IRFFFormatContext.dictionaryOptionWasApplied(-1))
    }

    func testSelectedSetupErrorRequiresBothTrackErrors() {
        let streamNotFound = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        XCTAssertNil(IRFFFormatContext.selectedSetupError(videoError: nil, audioError: audioOpen))
        XCTAssertNil(IRFFFormatContext.selectedSetupError(videoError: streamNotFound, audioError: nil))
    }

    func testSelectedSetupErrorPrefersAudioWhenVideoStreamIsMissing() throws {
        let streamNotFound = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        let selected = try XCTUnwrap(IRFFFormatContext.selectedSetupError(videoError: streamNotFound, audioError: audioOpen))

        XCTAssertEqual(selected, audioOpen)
    }

    func testSelectedSetupErrorDefaultsToVideoError() throws {
        let videoOpen = NSError(
            domain: "video",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )
        let audioOpen = NSError(
            domain: "audio",
            code: Int(IRFFDecoderErrorCode.codecOpen2.rawValue)
        )

        let selected = try XCTUnwrap(IRFFFormatContext.selectedSetupError(videoError: videoOpen, audioError: audioOpen))

        XCTAssertEqual(selected, videoOpen)
    }

    func testVideoAspectUsesFiniteRatioAndFallsBackForInvalidDimensions() {
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 1920, height: 1080), 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 0, height: 1080), 0)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: 1920, height: 0), 0)
        XCTAssertEqual(IRFFFormatContext.videoAspect(width: -1, height: 1080), 0)
    }

    func testVideoPresentationSizeRejectsInvalidDimensions() {
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 1920, height: 1080), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 0, height: 1080), .zero)
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: 1920, height: 0), .zero)
        XCTAssertEqual(IRFFFormatContext.presentationSize(width: -1, height: 1080), .zero)
    }

    func testAudioTrackSelectionActionOnlySelectsDifferentAvailableTracks() {
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: 1, containsRequestedTrack: true),
            .select
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: nil, containsRequestedTrack: true),
            .select
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 1, currentIndex: 1, containsRequestedTrack: true),
            .noChange
        )
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: 2, currentIndex: 1, containsRequestedTrack: false),
            .noChange
        )
    }

    func testAudioTrackSelectionActionRejectsNegativeRequestedIndex() {
        XCTAssertEqual(
            IRFFFormatContext.audioTrackSelectionAction(requestedIndex: -1, currentIndex: 0, containsRequestedTrack: true),
            .noChange
        )
    }

    func testSeekTimestampConvertsSecondsToFFmpegTimebase() {
        XCTAssertEqual(IRFFFormatContext.seekTimestamp(for: 1.5), 1_500_000)
        XCTAssertEqual(IRFFFormatContext.seekTimestamp(for: 0), 0)
    }

    func testSeekTimestampRejectsInvalidOrOverflowingTimes() {
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: -0.1))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: .nan))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: .infinity))
        XCTAssertNil(IRFFFormatContext.seekTimestamp(for: Double(Int64.max)))
    }

    func testSeekFileIgnoresMissingFormatContext() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        context.seekFile(withFFTimebase: 1)
    }

    func testReadFrameReturnsFailureWhenFormatContextIsMissing() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)
        var packet = AVPacket()

        XCTAssertLessThan(context.readFrame(&packet), 0)
    }

    func testDerivedFormatValuesUseDefaultsBeforeStreamIsOpened() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertEqual(context.bitrate, 0)
        XCTAssertEqual(context.duration, 0)
    }

    func testRuntimeReceivesImmutableContentHeaderConfiguration() {
        let expected = [
            "Authorization": "Bearer value",
            "X-Playback": "primary"
        ]
        let observed =
            LockedFormatContextRuntimeValue<
                [String: String]?
            >(nil)
        let closeCount =
            LockedFormatContextRuntimeValue(0)
        let runtime =
            IRFFFormatContextRuntime(
                makeGeneration: {
                    _,
                    _,
                    headers,
                    interruptState in
                    observed.withValue {
                        $0 = headers
                    }
                    return .success(
                        makeFormatContextGeneration(
                            interruptState:
                                interruptState,
                            closeCount:
                                closeCount
                        )
                    )
                },
                seekFrame: { _, _ in 0 },
                readFrame: { _, _ in
                    IR_AVERROR_EOF
                }
            )
        let context = IRFFFormatContext(
            contentURL:
                URL(fileURLWithPath:
                        "/tmp/headers.mp4"),
            videoFormat: .mpeg4,
            contentHeaders: expected,
            runtime: runtime
        )
        defer { context.destroy() }

        context.setupSync()

        XCTAssertEqual(
            observed.value,
            expected
        )
    }

    func testSetupSyncOpensGeneratedVideoFileAndInitializesVideoTrack() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(contentURL: url, videoFormat: .mpeg4)
        addTeardownBlock {
            context.destroy()
        }

        context.setupSync()

        XCTAssertNil(context.error)
        XCTAssertEqual(context.diagnostics.phase, .active)
        XCTAssertTrue(context.diagnostics.hasGeneration)
        XCTAssertTrue(context.diagnostics.hasFormatContext)
        XCTAssertTrue(context.diagnostics.hasVideoCodecContext)
        XCTAssertTrue(context.videoEnable)
        XCTAssertFalse(context.audioEnable)
        XCTAssertEqual(context.videoTrack?.type, .video)
        XCTAssertEqual(context.videoTracks.map(\.type), [.video])
        XCTAssertTrue(context.audioTracks.isEmpty)
        XCTAssertNotNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)
        XCTAssertEqual(context.videoPresentationSize, CGSize(width: 16, height: 16))
        XCTAssertEqual(context.videoAspect, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(context.videoTimebase, 0)
        XCTAssertGreaterThan(context.videoFPS, 0)
        XCTAssertGreaterThanOrEqual(context.duration, 0)

        var packet = AVPacket()
        XCTAssertGreaterThanOrEqual(context.readFrame(&packet), 0)
        IRFFFormatContext.releasePacket(&packet)

        context.seekFile(withFFTimebase: 0)

        let originalCodecContext = context.videoCodecContext
        context.setupSync()
        XCTAssertEqual(context.videoCodecContext, originalCodecContext)
        XCTAssertEqual(context.diagnostics.phase, .active)
    }

    func testContentURLStringUsesFilePathOrAbsoluteURL() {
        let fileContext = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/sample movie.mp4"),
            videoFormat: .mpeg4
        )
        let remoteContext = IRFFFormatContext(
            contentURL: URL(string: "https://example.com/video.m3u8?token=abc")!,
            videoFormat: .mpeg4
        )

        XCTAssertEqual(fileContext.contentURLString, "/tmp/sample movie.mp4")
        XCTAssertEqual(remoteContext.contentURLString, "https://example.com/video.m3u8?token=abc")
    }

    func testSelectingMissingAudioTrackLeavesContextUnchanged() {
        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        let result = context.selectAudioTrackIndexResult(0)

        XCTAssertNil(result.error)
        XCTAssertFalse(result.didChangeTrack)
        XCTAssertFalse(context.containAudioTrack(0))
        XCTAssertNil(context.selectAudioTrackIndex(0))
    }

    func testDurationSecondsPreservesNoPTSBehavior() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: Int64.min), TimeInterval(MAXFLOAT))
    }

    func testDurationSecondsUsesFractionalFFmpegTimebase() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: 1_500_000), 1.5, accuracy: 0.0001)
    }

    func testDurationSecondsRejectsNegativeDurations() {
        XCTAssertEqual(IRFFFormatContext.durationSeconds(from: -1), 0)
    }

    func testBitrateKbpsConvertsPositiveValues() {
        XCTAssertEqual(IRFFFormatContext.bitrateKbps(from: 1_500), 1.5, accuracy: 0.0001)
    }

    func testBitrateKbpsRejectsNegativeValues() {
        XCTAssertEqual(IRFFFormatContext.bitrateKbps(from: -1), 0)
    }

    func testInterruptCallbackIgnoresMissingContextAndUsesDelegateDecision() {
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: nil), 0)

        let context = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)
        let delegate = FormatContextInterruptDelegate(shouldInterrupt: true)
        let interruptState = IRFFFormatContextInterruptState()
        interruptState.bind(context: context)
        interruptState.setDelegate(delegate)
        let refCon = interruptState.makeRetainedCallbackReference()
        defer {
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference(refCon)
        }

        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 1)

        delegate.shouldInterrupt = false
        XCTAssertEqual(ffmpeg_interrupt_callback(ctx: refCon), 0)
    }

    func testInterruptCallbackCanReadSnapshotRejectNestedSeekAndDeferDestroyUntilReadReturns() {
        let closeCount = LockedFormatContextRuntimeValue(0)
        let callbackResult = LockedFormatContextRuntimeValue<Int32>(0)
        let resourceClosedBeforeReadReturned =
            LockedFormatContextRuntimeValue(false)
        let seekCallCount = LockedFormatContextRuntimeValue(0)
        let runtime = makeFormatContextRuntime(
            closeCount: closeCount,
            seekFrame: { _, _ in
                seekCallCount.withValue { $0 += 1 }
                return 0
            },
            readFrame: { formatContext, _ in
                let result = ffmpeg_interrupt_callback(
                    ctx: formatContext.pointee
                        .interrupt_callback.opaque
                )
                callbackResult.withValue { $0 = result }
                resourceClosedBeforeReadReturned.withValue {
                    $0 = closeCount.value != 0
                }
                return -451
            }
        )
        let context = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/injected.mp4"),
            videoFormat: .mpeg4,
            runtime: runtime
        )
        let delegate = ReentrantFormatContextInterruptDelegate(
            closeCount: closeCount
        )
        context.delegate = delegate
        context.setupSync()
        XCTAssertEqual(context.diagnostics.phase, .active)

        var packet = AVPacket()
        let readResult = context.readFrame(&packet)

        XCTAssertEqual(readResult, -451)
        XCTAssertEqual(callbackResult.value, 1)
        XCTAssertEqual(
            delegate.observedMetadata["title"] as? String,
            "published"
        )
        XCTAssertEqual(delegate.observedDuration, 2)
        XCTAssertFalse(delegate.nestedSeekWasAccepted)
        XCTAssertFalse(delegate.resourceWasClosedInsideCallback)
        XCTAssertFalse(resourceClosedBeforeReadReturned.value)
        XCTAssertEqual(seekCallCount.value, 0)
        XCTAssertEqual(closeCount.value, 1)
        XCTAssertEqual(context.diagnostics.phase, .closed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
        XCTAssertTrue(
            context.diagnostics.interruptCloseRequested
        )
    }

    func testBlockedReadAllowsSnapshotMetadataAndSerializesSeekUntilReadExits() {
        let readEntered = DispatchSemaphore(value: 0)
        let releaseRead = DispatchSemaphore(value: 0)
        let readFinished = DispatchSemaphore(value: 0)
        let metadataFinished = DispatchSemaphore(value: 0)
        let seekAttempted = DispatchSemaphore(value: 0)
        let seekFinished = DispatchSemaphore(value: 0)
        let closeCount = LockedFormatContextRuntimeValue(0)
        let readResult = LockedFormatContextRuntimeValue<Int32>(0)
        let observedMetadata =
            LockedFormatContextRuntimeValue<(String?, TimeInterval, TimeInterval)>(
                (nil, 0, 0)
            )
        let seekResult = LockedFormatContextRuntimeValue(false)
        let seekTimestamps =
            LockedFormatContextRuntimeValue<[Int64]>([])
        let runtime = makeFormatContextRuntime(
            closeCount: closeCount,
            seekFrame: { _, timestamp in
                seekTimestamps.withValue { $0.append(timestamp) }
                return 0
            },
            readFrame: { formatContext, _ in
                // A getter must use the setup snapshot, not touch this
                // raw context while the read operation owns it.
                formatContext.pointee.duration =
                    9 * Int64(AV_TIME_BASE)
                readEntered.signal()
                guard releaseRead.wait(timeout: .now() + 3)
                        == .success else {
                    return -452
                }
                return 37
            }
        )
        let context = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/injected.mp4"),
            videoFormat: .mpeg4,
            runtime: runtime
        )
        context.setupSync()
        XCTAssertEqual(context.duration, 2)

        DispatchQueue.global().async {
            var packet = AVPacket()
            let result = context.readFrame(&packet)
            readResult.withValue { $0 = result }
            readFinished.signal()
        }
        XCTAssertEqual(
            readEntered.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            observedMetadata.withValue {
                $0 = (
                    context.metadata["title"] as? String,
                    context.duration,
                    context.bitrate
                )
            }
            metadataFinished.signal()
        }
        XCTAssertEqual(
            metadataFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(observedMetadata.value.0, "published")
        XCTAssertEqual(observedMetadata.value.1, 2)
        XCTAssertEqual(observedMetadata.value.2, 8)

        DispatchQueue.global().async {
            seekAttempted.signal()
            let result = context.seekFile(withFFTimebase: 1)
            seekResult.withValue { $0 = result }
            seekFinished.signal()
        }
        XCTAssertEqual(
            seekAttempted.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            seekFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )
        XCTAssertTrue(seekTimestamps.value.isEmpty)

        releaseRead.signal()
        XCTAssertEqual(
            readFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(
            seekFinished.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertEqual(readResult.value, 37)
        XCTAssertTrue(seekResult.value)
        XCTAssertEqual(seekTimestamps.value, [Int64(AV_TIME_BASE)])

        context.destroy()
        XCTAssertEqual(closeCount.value, 1)
    }

    func testFailedSetupPublishesNoPartialGenerationAndIsNotRetried() {
        let context = IRFFFormatContext(
            contentURL: URL(
                fileURLWithPath:
                    "/tmp/irplayer-definitely-missing-\(UUID()).mp4"
            ),
            videoFormat: .mpeg4
        )

        context.setupSync()

        XCTAssertNotNil(context.error)
        XCTAssertEqual(context.diagnostics.phase, .failed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
        XCTAssertFalse(context.diagnostics.hasFormatContext)
        XCTAssertNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)

        let originalError = context.error
        context.setupSync()
        XCTAssertEqual(context.error, originalError)
        XCTAssertEqual(context.diagnostics.phase, .failed)
    }

    func testDestroyIsIdempotentTerminalAndClearsPublishedGeneration()
        throws
    {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(
            contentURL: url,
            videoFormat: .mpeg4
        )
        context.setupSync()
        XCTAssertEqual(context.diagnostics.phase, .active)

        context.destroy()
        context.destroy()
        context.setupSync()

        XCTAssertEqual(context.diagnostics.phase, .closed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
        XCTAssertFalse(context.diagnostics.hasFormatContext)
        XCTAssertTrue(context.diagnostics.interruptCloseRequested)
        XCTAssertFalse(context.videoEnable)
        XCTAssertFalse(context.audioEnable)
        XCTAssertNil(context.videoCodecContext)
        XCTAssertNil(context.audioCodecContext)
        XCTAssertEqual(context.duration, 0)
        XCTAssertEqual(context.bitrate, 0)
        var packet = AVPacket()
        XCTAssertLessThan(context.readFrame(&packet), 0)
    }

    func testConcurrentReadGettersSeekAndDestroyRemainSafe() throws {
        let url = try makeTinyVideoFile()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let context = IRFFFormatContext(
            contentURL: url,
            videoFormat: .mpeg4
        )
        context.setupSync()
        try XCTSkipIf(
            context.error != nil,
            "Generated fixture could not be opened."
        )

        DispatchQueue.concurrentPerform(iterations: 500) { index in
            switch index % 6 {
            case 0:
                var packet = AVPacket()
                _ = context.readFrame(&packet)
                IRFFFormatContext.releasePacket(&packet)
            case 1:
                _ = context.duration
            case 2:
                _ = context.videoTracks
            case 3:
                context.seekFile(withFFTimebase: 0)
            case 4:
                _ = context.diagnostics
            default:
                context.destroy()
            }
        }

        XCTAssertEqual(context.diagnostics.phase, .closed)
        XCTAssertFalse(context.diagnostics.hasGeneration)
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var context: IRFFFormatContext? = IRFFFormatContext(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4
        )
        XCTAssertNotNil(context)

        let output = captureStandardOutput {
            context = nil
        }

        XCTAssertEqual(output, "")
    }
}

private final class ReentrantFormatContextInterruptDelegate:
    IRFFFormatContextDelegate
{
    private let closeCount: LockedFormatContextRuntimeValue<Int>

    private(set) var observedMetadata: [AnyHashable: Any] = [:]
    private(set) var observedDuration: TimeInterval = 0
    private(set) var nestedSeekWasAccepted = true
    private(set) var resourceWasClosedInsideCallback = true

    init(closeCount: LockedFormatContextRuntimeValue<Int>) {
        self.closeCount = closeCount
    }

    func formatContextNeedInterrupt(
        _ formatContext: IRFFFormatContext
    ) -> Bool {
        observedMetadata = formatContext.metadata
        observedDuration = formatContext.duration
        nestedSeekWasAccepted = formatContext.seekFile(
            withFFTimebase: 1
        )
        formatContext.destroy()
        resourceWasClosedInsideCallback = closeCount.value != 0
        return false
    }
}

private final class LockedFormatContextRuntimeValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

private func makeFormatContextRuntime(
    closeCount: LockedFormatContextRuntimeValue<Int>,
    seekFrame: @escaping (
        UnsafeMutablePointer<AVFormatContext>,
        Int64
    ) -> Int32,
    readFrame: @escaping (
        UnsafeMutablePointer<AVFormatContext>,
        UnsafeMutablePointer<AVPacket>
    ) -> Int32
) -> IRFFFormatContextRuntime {
    IRFFFormatContextRuntime(
        makeGeneration: {
            _,
            _,
            _,
            interruptState in
            .success(
                makeFormatContextGeneration(
                    interruptState: interruptState,
                    closeCount: closeCount
                )
            )
        },
        seekFrame: seekFrame,
        readFrame: readFrame
    )
}

private func makeFormatContextGeneration(
    interruptState: IRFFFormatContextInterruptState,
    closeCount: LockedFormatContextRuntimeValue<Int>
) -> IRFFFormatContextGeneration {
    let formatContext =
        UnsafeMutablePointer<AVFormatContext>.allocate(capacity: 1)
    formatContext.initialize(to: AVFormatContext())
    formatContext.pointee.duration = 2 * Int64(AV_TIME_BASE)
    formatContext.pointee.bit_rate = 8_000

    let callbackReference =
        interruptState.makeRetainedCallbackReference()
    formatContext.pointee.interrupt_callback.callback =
        ffmpeg_interrupt_callback
    formatContext.pointee.interrupt_callback.opaque =
        callbackReference

    let resourceRuntime = IRFFFormatContextResourceRuntime(
        freeCodecContext: { $0 = nil },
        closeInputContext: { context in
            if let context {
                closeCount.withValue { $0 += 1 }
                context.deinitialize(count: 1)
                context.deallocate()
            }
            context = nil
        },
        releaseCallbackReference: {
            IRFFFormatContextInterruptState
                .releaseRetainedCallbackReference($0)
        }
    )
    let generation = IRFFFormatContextGeneration(
        formatContext: formatContext,
        callbackReference: callbackReference,
        runtime: resourceRuntime
    )
    generation.metadata = ["title": "published"]
    return generation
}

func makeTinyVideoFile() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irff-format-context-\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: url)

    let writer: AVAssetWriter
    do {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    } catch {
        throw XCTSkip("AVAssetWriter unavailable: \(error)")
    }

    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16
        ]
    )
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 16,
            kCVPixelBufferHeightKey as String: 16
        ]
    )

    guard writer.canAdd(input) else {
        throw XCTSkip("Cannot add video input to AVAssetWriter.")
    }
    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 1)
    }
    writer.startSession(atSourceTime: .zero)

    guard let pool = adaptor.pixelBufferPool else {
        throw XCTSkip("AVAssetWriter did not provide a pixel buffer pool.")
    }

    for frameIndex in 0..<2 {
        guard input.isReadyForMoreMediaData else {
            throw XCTSkip("AVAssetWriter input was not ready for pixel buffers.")
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("Could not create pixel buffer: \(status).")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: 30)
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 2)
        }
    }

    input.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 30) == .success else {
        throw XCTSkip("Timed out while writing tiny video fixture.")
    }
    guard writer.status == .completed else {
        throw writer.error ?? NSError(domain: "IRFFFormatContextTests", code: 3)
    }

    return url
}
