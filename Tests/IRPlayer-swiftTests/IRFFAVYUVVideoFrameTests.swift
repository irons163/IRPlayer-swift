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

    func testYUVChannelFilterNeedSizeCheckedRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 0, height: 4, channelCount: 1))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 4, height: 0, channelCount: 1))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 4, height: 4, channelCount: 0))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: .max, width: .max, height: 2, channelCount: 2))
    }

    func testYUVChannelFilterNeedSizeCheckedUsesAdjustedWidth() {
        XCTAssertEqual(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 8, height: 3, channelCount: 2), 24)
    }
}

final class IRPLFImageTests: XCTestCase {

    func testRGBDataByteCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 0, width: 4, height: 4))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 12, width: 0, height: 4))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 12, width: 4, height: 0))
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: Int.max, width: 4, height: 2))
    }

    func testRGBDataByteCountRequiresRowsWideEnoughForRGBPixels() {
        XCTAssertNil(IRPLFImageRGBDataByteCount(linesize: 11, width: 4, height: 2))
        XCTAssertEqual(IRPLFImageRGBDataByteCount(linesize: 12, width: 4, height: 2), 24)
    }
}
