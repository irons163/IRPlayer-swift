import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationTests: XCTestCase {

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoder.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoder.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoder.audioCodecContext(from: formatContext))
    }

    func testOperationSchedulingTreatsMissingOrFinishedOperationsAsSchedulable() {
        XCTAssertTrue(IRFFDecoder.needsScheduling(nil))

        let operation = BlockOperation {}
        XCTAssertFalse(IRFFDecoder.needsScheduling(operation))

        operation.start()
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(IRFFDecoder.needsScheduling(operation))
    }

    func testOperationHelpersIgnoreMissingInputsAndWireDependencies() {
        let queue = OperationQueue()
        queue.isSuspended = true

        let operation = BlockOperation {}
        let dependency = BlockOperation {}

        XCTAssertFalse(IRFFDecoder.addDependency(dependency, to: nil))
        XCTAssertFalse(IRFFDecoder.addDependency(nil, to: operation))
        XCTAssertTrue(IRFFDecoder.addDependency(dependency, to: operation))
        XCTAssertTrue(operation.dependencies.contains { $0 === dependency })

        XCTAssertFalse(IRFFDecoder.enqueue(nil, on: queue))
        XCTAssertFalse(IRFFDecoder.enqueue(operation, on: nil))
        XCTAssertTrue(IRFFDecoder.enqueue(operation, on: queue))
        XCTAssertTrue(queue.operations.contains { $0 === operation })

        queue.cancelAllOperations()
        queue.isSuspended = false
    }

    func testAudioPacketErrorUsesPacketResult() throws {
        XCTAssertNil(IRFFDecoder.audioPacketError(fromPacketResult: 0))

        let error = try XCTUnwrap(IRFFDecoder.audioPacketError(fromPacketResult: -1))
        XCTAssertEqual(error.code, IRFFDecoderErrorCode.codecAudioSendPacket.rawValue)
        XCTAssertTrue(error.domain.contains("ffmpeg code: -1"))
    }

    func testReleaseDoesNotPrintDebugOutput() {
        var decoder: IRFFDecoder? = IRFFDecoder(
            contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"),
            videoFormat: .mpeg4,
            videoOutput: nil,
            audioOutput: nil
        )
        XCTAssertNotNil(decoder)

        let output = captureStandardOutput {
            decoder = nil
        }

        XCTAssertEqual(output, "")
    }
}
