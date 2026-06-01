import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRFFDecoderOperationTests: XCTestCase {

    func testCodecContextHelpersRejectMissingOrDisabledFormatContext() {
        let formatContext = IRFFFormatContext(contentURL: URL(fileURLWithPath: "/tmp/missing.mp4"), videoFormat: .mpeg4)

        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: nil))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.videoCodecContext(from: formatContext))
        XCTAssertNil(IRFFDecoderCodecContextPolicy.audioCodecContext(from: formatContext))
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
