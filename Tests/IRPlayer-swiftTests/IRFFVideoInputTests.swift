import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFVideoInputTests: XCTestCase {

    func testInitializerDefaultsToDisplayViewOutputWithoutVideoOutput() {
        let input = IRFFVideoInput()

        XCTAssertNil(input.videoOutput)
        XCTAssertEqual(input.outputType, .displayView)
    }

    func testInitializerStoresVideoOutputAndOutputType() {
        let output = RecordingFFDecoderVideoOutput()
        let input = IRFFVideoInput(videoOutput: output, outputType: .decoder)

        XCTAssertTrue(input.videoOutput === output)
        XCTAssertEqual(input.outputType, .decoder)
    }

    func testDefaultDataSourceAlwaysHandlesPacketsAndProducesNoFrame() {
        let input = IRFFVideoInput()
        var packet = AVPacket()
        packet.duration = 4

        var codecContext = AVCodecContext()
        withUnsafeMutablePointer(to: &codecContext) { codecContextPointer in
            let info = IRFFVideoDecoderInfo(codecContext: codecContextPointer,
                                            videoToolBoxEnable: false,
                                            maxDecodeDuration: 2,
                                            timebase: 0.25,
                                            fps: 30)

            XCTAssertTrue(input.shouldHandle(info, decodeFrame: packet))
            XCTAssertNil(input.videoDecoder(info, decodeFrame: packet))
        }
    }
}

private final class RecordingFFDecoderVideoOutput: NSObject, IRFFDecoderVideoOutput {
    private(set) var receivedFrames: [IRFFVideoFrame] = []

    func send(videoFrame frame: IRFFVideoFrame) {
        receivedFrames.append(frame)
    }
}
