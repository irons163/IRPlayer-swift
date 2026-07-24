import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRYUVImageConversionSessionTests:
    XCTestCase
{
    func testConfigurationRejectsInvalidOrUnrepresentableGeometry() {
        XCTAssertNil(
            IRYUVImageConversionConfiguration(
                width: 0,
                height: 1
            )
        )
        XCTAssertNil(
            IRYUVImageConversionConfiguration(
                width: 1,
                height: 0
            )
        )
        XCTAssertNil(
            IRYUVImageConversionConfiguration(
                width: Int(Int32.max) / 3 + 1,
                height: 1
            )
        )
        XCTAssertNil(
            IRYUVImageConversionConfiguration(
                width: Int.max,
                height: 1
            )
        )

        XCTAssertEqual(
            IRYUVImageConversionConfiguration(
                width: 4,
                height: 3
            ),
            IRYUVImageConversionConfiguration(
                width: 4,
                height: 3
            )
        )
        let configuration =
            IRYUVImageConversionConfiguration(
                width: 4,
                height: 3
            )
        XCTAssertEqual(configuration?.outputLineSize, 12)
        XCTAssertEqual(configuration?.outputByteCount, 36)
    }

    func testContextCreationFailureDoesNotAllocateOrFree() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let runtime = makeRuntime(
            events: events,
            shouldFailContext: true
        )

        XCTAssertNil(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: runtime
            )
        )
        XCTAssertEqual(events.value, ["makeContext"])
    }

    func testOutputAllocationFailureFreesPartialContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let runtime = makeRuntime(
            events: events,
            shouldFailOutput: true
        )

        XCTAssertNil(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: runtime
            )
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "free"]
        )
    }

    func testShortOutputAllocationFreesPartialContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let runtime = makeRuntime(
            events: events,
            outputCapacity: 1
        )

        XCTAssertNil(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: runtime
            )
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "free"]
        )
    }

    func testConversionPublishesManagedBytesAndReusesCapacity() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(events: events)
            )
        )
        let source = try XCTUnwrap(
            UnsafePointer<UInt8>(bitPattern: 0x2000)
        )
        var firstBytes: [UInt8] = []
        var secondBytes: [UInt8] = []

        let firstOutcome = session.withConvertedRGB(
            sourceData: [source],
            sourceLineSizes: [6]
        ) {
            bytes,
            configuration in
            firstBytes = Array(bytes)
            XCTAssertEqual(configuration.outputLineSize, 6)
            return true
        }
        let capacity = session.diagnostics.outputCapacity
        let secondOutcome = session.withConvertedRGB(
            sourceData: [source],
            sourceLineSizes: [6]
        ) {
            bytes,
            _ in
            secondBytes = Array(bytes)
            return true
        }

        XCTAssertEqual(firstOutcome, .converted)
        XCTAssertEqual(secondOutcome, .converted)
        XCTAssertEqual(
            firstBytes,
            Array(UInt8(1)...UInt8(12))
        )
        XCTAssertEqual(firstBytes, secondBytes)
        XCTAssertEqual(capacity, 12)
        XCTAssertEqual(
            session.diagnostics,
            IRYUVImageConversionDiagnostics(
                isClosed: false,
                hasContext: true,
                outputCapacity: 12
            )
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "scale", "scale"]
        )
    }

    func testScaleFailureDoesNotInvokeConsumer() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(
                    events: events,
                    scaleResult: -7
                )
            )
        )
        var consumed = false

        let outcome = session.withConvertedRGB(
            sourceData: [
                UnsafePointer<UInt8>(bitPattern: 0x2000)
            ],
            sourceLineSizes: [6]
        ) {
            _,
            _ in
            consumed = true
            return true
        }

        XCTAssertEqual(outcome, .scaleFailed(-7))
        XCTAssertFalse(consumed)
    }

    func testIncompleteOutputDoesNotInvokeConsumer() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(
                    events: events,
                    scaleResult: 1
                )
            )
        )
        var consumed = false

        let outcome = session.withConvertedRGB(
            sourceData: [
                UnsafePointer<UInt8>(bitPattern: 0x2000)
            ],
            sourceLineSizes: [6]
        ) {
            _,
            _ in
            consumed = true
            return true
        }

        XCTAssertEqual(
            outcome,
            .incompleteOutput(expected: 2, actual: 1)
        )
        XCTAssertFalse(consumed)
    }

    func testInvalidSourceAndConsumerRejectionAreTyped() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(events: events)
            )
        )

        XCTAssertEqual(
            session.withConvertedRGB(
                sourceData: [],
                sourceLineSizes: []
            ) {
                _,
                _ in
                XCTFail("invalid input must not be consumed")
                return true
            },
            .invalidSource
        )
        XCTAssertEqual(
            session.withConvertedRGB(
                sourceData: [
                    UnsafePointer<UInt8>(
                        bitPattern: 0x2000
                    )
                ],
                sourceLineSizes: [6]
            ) {
                _,
                _ in false
            },
            .consumerRejected
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "scale"]
        )
    }

    func testCloseIsTerminalAndFreesExactlyOnce() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(events: events)
            )
        )

        session.close()
        session.close()

        XCTAssertEqual(
            session.diagnostics,
            IRYUVImageConversionDiagnostics(
                isClosed: true,
                hasContext: false,
                outputCapacity: 0
            )
        )
        XCTAssertEqual(
            session.withConvertedRGB(
                sourceData: [
                    UnsafePointer<UInt8>(
                        bitPattern: 0x2000
                    )
                ],
                sourceLineSizes: [6]
            ) {
                _,
                _ in true
            },
            .closed
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "free"]
        )
    }

    func testCloseWaitsForActiveConversion() throws {
        let events =
            LockedDecoderResourceValue<[String]>([])
        let scaleStarted = DispatchSemaphore(value: 0)
        let allowScaleToFinish = DispatchSemaphore(value: 0)
        let conversionFinished = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)
        let session = try XCTUnwrap(
            IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(
                    events: events,
                    onScale: {
                        scaleStarted.signal()
                        _ = allowScaleToFinish.wait(
                            timeout: .now() + 2
                        )
                    }
                )
            )
        )

        DispatchQueue.global().async {
            let outcome = session.withConvertedRGB(
                sourceData: [
                    UnsafePointer<UInt8>(
                        bitPattern: 0x2000
                    )
                ],
                sourceLineSizes: [6]
            ) {
                _,
                _ in true
            }
            XCTAssertEqual(outcome, .converted)
            conversionFinished.signal()
        }
        XCTAssertEqual(
            scaleStarted.wait(timeout: .now() + 2),
            .success
        )

        DispatchQueue.global().async {
            session.close()
            closeFinished.signal()
        }
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 0.05),
            .timedOut
        )
        XCTAssertFalse(events.value.contains("free"))

        allowScaleToFinish.signal()
        XCTAssertEqual(
            conversionFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            closeFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "scale", "free"]
        )
    }

    func testDeinitFreesContext() {
        let events =
            LockedDecoderResourceValue<[String]>([])
        weak var weakSession: IRYUVImageConversionSession?

        autoreleasepool {
            let session = IRYUVImageConversionSession(
                width: 2,
                height: 2,
                sourcePixelFormat: AV_PIX_FMT_RGB24,
                runtime: makeRuntime(events: events)
            )
            weakSession = session
            XCTAssertNotNil(weakSession)
        }

        XCTAssertNil(weakSession)
        XCTAssertEqual(
            events.value,
            ["makeContext", "allocate", "free"]
        )
    }

    private func makeRuntime(
        events: LockedDecoderResourceValue<[String]>,
        shouldFailContext: Bool = false,
        shouldFailOutput: Bool = false,
        outputCapacity: Int? = nil,
        scaleResult: Int32? = nil,
        onScale: (() -> Void)? = nil
    ) -> IRYUVImageConversionRuntime {
        IRYUVImageConversionRuntime(
            makeContext: {
                _,
                _ in
                events.withValue {
                    $0.append("makeContext")
                }
                return shouldFailContext
                    ? nil
                    : OpaquePointer(bitPattern: 0x1000)
            },
            allocateOutput: { requestedCapacity in
                events.withValue {
                    $0.append("allocate")
                }
                guard !shouldFailOutput else {
                    return nil
                }
                return [UInt8](
                    repeating: 0,
                    count: outputCapacity
                        ?? requestedCapacity
                )
            },
            scale: {
                _,
                _,
                _,
                configuration,
                output in
                events.withValue {
                    $0.append("scale")
                }
                onScale?()
                for index in
                    0..<configuration.outputByteCount
                {
                    output[index] = UInt8(index + 1)
                }
                return scaleResult ?? configuration.height
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
