import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFToolsTests: XCTestCase {

    func testRuntimeDebugOutputIsSilentByDefault() {
        XCTAssertFalse(IRFFRuntimeDebugOutput.isEnabled)

        let output = captureStandardOutput {
            IRFFRuntimeDebugOutput.write("runtime trace")
        }

        XCTAssertEqual(output, "")
    }

    func testRuntimeDebugOutputWrapperMatchesPolicy() {
        XCTAssertEqual(IRFFRuntimeDebugOutput.isEnabled, IRFFRuntimeDebugOutputPolicy.isEnabled)
        XCTAssertFalse(IRFFRuntimeDebugOutputPolicy.isEnabled)

        let output = captureStandardOutput {
            IRFFRuntimeDebugOutputPolicy.write("runtime trace")
        }

        XCTAssertEqual(output, "")
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

    func testFFLogPolicyFormatsValidMessagesAndRejectsInvalidUTF8() throws {
        "codec %@ %d".withCString { format in
            withVaList(["ok", 7]) { args in
                XCTAssertEqual(IRFFLogPolicy.message(format: format, args: args), "codec ok 7")
            }
        }

        let invalidFormat: [CChar] = [-1, 0]

        try invalidFormat.withUnsafeBufferPointer { formatBuffer in
            let format = try XCTUnwrap(formatBuffer.baseAddress)
            withVaList([]) { args in
                XCTAssertNil(IRFFLogPolicy.message(format: format, args: args))
            }
        }
    }

    func testFFLogPolicyIsSilentByDefault() {
        let output = captureStandardOutput {
            "codec %@".withCString { format in
                withVaList(["ok"]) { args in
                    IRFFLogPolicy.write(context: nil, level: 0, format: format, args: args)
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

    func testCheckErrorWrappersRemainSourceCompatible() throws {
        XCTAssertNil(IRFFCheckError(0))
        XCTAssertNil(IRFFErrorPolicy.error(result: 0, errorCode: -1))

        let wrapperError = try XCTUnwrap(IRFFCheckErrorCode(-1, errorCode: 42))
        let policyError = try XCTUnwrap(IRFFErrorPolicy.error(result: -1, errorCode: 42))
        XCTAssertEqual(wrapperError.code, policyError.code)
        XCTAssertEqual(wrapperError.domain, policyError.domain)
    }

    func testFinitePositiveValueUsesFallbackForInvalidValues() {
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.nan, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(.infinity, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(0, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(-1, defaultValue: 1), 1)
        XCTAssertEqual(IRFFFinitePositiveValueOrDefault(2.5, defaultValue: 1), 2.5)
    }

    func testStreamTimingWrappersRemainSourceCompatible() {
        var stream = AVStream()
        stream.time_base = AVRational(num: 1, den: 1_000)
        stream.avg_frame_rate = AVRational(num: 30, den: 1)

        withUnsafePointer(to: &stream) { streamPointer in
            XCTAssertEqual(
                IRFFFinitePositiveValueOrDefault(.nan, defaultValue: 1),
                IRFFStreamTimingPolicy.finitePositiveValueOrDefault(.nan, defaultValue: 1)
            )
            XCTAssertEqual(
                IRFFStreamGetTimebase(streamPointer, defaultTimebase: 1),
                IRFFStreamTimingPolicy.timebase(streamPointer, defaultTimebase: 1),
                accuracy: 0.0001
            )
            XCTAssertEqual(
                IRFFStreamGetFPS(streamPointer, timebase: 0.001),
                IRFFStreamTimingPolicy.fps(streamPointer, timebase: 0.001),
                accuracy: 0.0001
            )
        }
    }

    func testDictionaryBridgeWrapperRemainsSourceCompatible() {
        let dictionary: OpaquePointer? = nil

        XCTAssertEqual(
            IRFFFoundationBrigeOfAVDictionary(dictionary),
            IRFFDictionaryPolicy.foundationDictionary(from: dictionary)
        )
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
}
