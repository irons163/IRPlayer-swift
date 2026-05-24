import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFAVYUVVideoFrameTests: XCTestCase {

    func testImageReturnsNilWhenFrameDataIsMissing() {
        let frame = IRFFAVYUVVideoFrame()

        let image: IRPLFImage? = frame.image()

        XCTAssertNil(image)
    }

    func testSetFrameDataIgnoresMissingPlaneData() {
        var avFrame = AVFrame()
        avFrame.format = 0
        let frame = IRFFAVYUVVideoFrame()

        withUnsafePointer(to: &avFrame) { pointer in
            frame.setFrameData(pointer, width: 4, height: 4)
        }

        XCTAssertNil(frame.image())
    }
}
