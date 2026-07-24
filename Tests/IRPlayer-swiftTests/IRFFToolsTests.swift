import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFToolsTests: XCTestCase {

    func testRuntimeDebugOutputIsSilentByDefault() {
        XCTAssertFalse(IRFFRuntimeDebugOutput.isEnabled)
        var evaluationCount = 0

        let output = captureStandardOutput {
            IRFFRuntimeDebugOutput.write({
                evaluationCount += 1
                return "runtime trace"
            }())
        }

        XCTAssertEqual(output, "")
        XCTAssertEqual(evaluationCount, 0)
    }

    func testLegacyLogFunctionsAreSilentByDefault() {
        let output = captureStandardOutput {
            IRFFErrorLog("ffmpeg error trace")
            IRPlayerLog("player trace")
        }

        XCTAssertEqual(output, "")
    }

    func testFFLogIgnoresInvalidUTF8FormatString() throws {
        let invalidFormat: [CChar] = [-1, 0]

        try invalidFormat.withUnsafeBufferPointer { formatBuffer in
            let format = try XCTUnwrap(formatBuffer.baseAddress)
            withVaList([]) { args in
                IRFFLog(context: nil, level: 0, format: format, args: args)
            }
        }
    }

    func testFFLogFormattingAcceptsValidMessagesAndRejectsInvalidUTF8() throws {
        "codec %@ %d".withCString { format in
            withVaList(["ok", 7]) { args in
                XCTAssertEqual(
                    IRFFLogFormatting.message(
                        format: format,
                        args: args
                    ),
                    "codec ok 7"
                )
            }
        }

        let invalidFormat: [CChar] = [-1, 0]

        try invalidFormat.withUnsafeBufferPointer { formatBuffer in
            let format = try XCTUnwrap(formatBuffer.baseAddress)
            withVaList([]) { args in
                XCTAssertNil(
                    IRFFLogFormatting.message(
                        format: format,
                        args: args
                    )
                )
            }
        }
    }

    func testFFLogFormattingBuildsPrefixedLogLines() {
        XCTAssertEqual(
            IRFFLogFormatting.logLine(for: "codec ok"),
            "IRFFLog: codec ok"
        )
    }

    func testFFLogIsSilentByDefault() {
        let output = captureStandardOutput {
            "codec %@".withCString { format in
                withVaList(["ok"]) { args in
                    IRFFLog(
                        context: nil,
                        level: 0,
                        format: format,
                        args: args
                    )
                }
            }
        }

        XCTAssertEqual(output, "")
    }

    func testCheckErrorReturnsNilForSuccessAndUsesRequestedCodeForFailures() throws {
        XCTAssertNil(IRFFCheckError(0))
        XCTAssertNil(IRFFCheckErrorCode(1, errorCode: 99))

        let error = try XCTUnwrap(IRFFCheckErrorCode(-1, errorCode: 42))
        XCTAssertEqual(error.code, 42)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }

    func testCheckErrorConvenienceUsesDefaultCode() throws {
        XCTAssertNil(IRFFCheckError(0))

        let error = try XCTUnwrap(IRFFCheckError(-1))
        XCTAssertEqual(error.code, -1)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }

    func testFinitePositiveValueUsesFallbackForInvalidValues() {
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.infinity, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(0, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(-1, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(2.5, defaultValue: 1), 2.5)
    }

    func testFinitePositiveValueUsesSafeFallbackForInvalidDefaults() {
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: .nan), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: .infinity), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: 0), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: -1), 1)
    }

    func testStreamTimingUsesValidatedRationals() {
        var stream = AVStream()
        stream.time_base = AVRational(num: 1, den: 1_000)
        stream.avg_frame_rate = AVRational(num: 30, den: 1)

        withUnsafePointer(to: &stream) { streamPointer in
            XCTAssertEqual(
                IRFFStreamGetTimebase(
                    streamPointer,
                    defaultTimebase: 1
                ),
                0.001,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                IRFFStreamGetFPS(
                    streamPointer,
                    timebase: 0.001
                ),
                30,
                accuracy: 0.0001
            )
        }
    }

    func testStreamTimebaseFallsBackToFiniteValueForInvalidStreamAndDefault() {
        var stream = AVStream()
        stream.time_base = AVRational(num: 0, den: 0)

        let timebase = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetTimebase(streamPointer, defaultTimebase: 0)
        }

        XCTAssertEqual(timebase, 1)
        XCTAssertTrue(timebase.isFinite)
    }

    func testStreamFPSUsesRFrameRateWhenAverageFrameRateIsInvalid() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 24, den: 1)

        let fps = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetFPS(streamPointer, timebase: 0.001)
        }

        XCTAssertEqual(fps, 24, accuracy: 0.0001)
    }

    func testStreamFPSFallsBackToTimebaseWhenFrameRatesAreInvalid() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 0, den: 0)

        let fps = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetFPS(streamPointer, timebase: 0.02)
        }

        XCTAssertEqual(fps, 50, accuracy: 0.0001)
    }

    func testStreamFPSFallsBackToFiniteValueForInvalidRatesAndTimebase() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 0, den: 0)

        let fps = withUnsafePointer(to: &stream) { streamPointer in
            IRFFStreamGetFPS(streamPointer, timebase: 0)
        }

        XCTAssertEqual(fps, 1)
        XCTAssertTrue(fps.isFinite)
    }

    func testStreamFPSRejectsDerivedReciprocalOverflow() {
        var stream = AVStream()
        stream.avg_frame_rate = AVRational(num: 0, den: 0)
        stream.r_frame_rate = AVRational(num: 0, den: 0)

        let fps = withUnsafePointer(to: &stream) {
            streamPointer in
            IRFFStreamGetFPS(
                streamPointer,
                timebase: .leastNonzeroMagnitude
            )
        }

        XCTAssertEqual(fps, 1)
    }
}
