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

    func testSetFrameDataRejectsNonPositivePlaneLinesizes() {
        var y = [UInt8](repeating: 1, count: 16)
        var u = [UInt8](repeating: 2, count: 4)
        var v = [UInt8](repeating: 3, count: 4)
        var avFrame = AVFrame()
        avFrame.format = 0
        avFrame.linesize.0 = -4
        avFrame.linesize.1 = 2
        avFrame.linesize.2 = 2
        let frame = IRFFAVYUVVideoFrame()

        y.withUnsafeMutableBufferPointer { yBuffer in
            u.withUnsafeMutableBufferPointer { uBuffer in
                v.withUnsafeMutableBufferPointer { vBuffer in
                    avFrame.data.0 = yBuffer.baseAddress
                    avFrame.data.1 = uBuffer.baseAddress
                    avFrame.data.2 = vBuffer.baseAddress
                    withUnsafePointer(to: &avFrame) { pointer in
                        frame.setFrameData(pointer, width: 4, height: 4)
                    }
                }
            }
        }

        XCTAssertEqual(frame.width, 0)
        XCTAssertEqual(frame.height, 0)
        XCTAssertEqual(frame.size, 0)
        XCTAssertNil(frame.image())
    }

    func testShouldAcceptFrameDataRequiresDimensionsPlanesAndLinesizes() {
        XCTAssertFalse(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 0,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            )
        )
        XCTAssertFalse(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: false,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            )
        )
        XCTAssertFalse(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 0,
                linesizeU: 2,
                linesizeV: 2
            )
        )
        XCTAssertTrue(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            )
        )
    }

    func testStaticPolicyWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            ),
            IRFFAVYUVVideoFramePolicy.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            )
        )
        XCTAssertEqual(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: false,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            ),
            IRFFAVYUVVideoFramePolicy.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: false,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 4,
                linesizeU: 2,
                linesizeV: 2
            )
        )
        XCTAssertEqual(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 0,
                linesizeU: 2,
                linesizeV: 2
            ),
            IRFFAVYUVVideoFramePolicy.shouldAcceptFrameData(
                width: 4,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 0,
                linesizeU: 2,
                linesizeV: 2
            )
        )
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

    func testYUVImageDimensions32RejectsInvalidOrOverflowingDimensions() {
        XCTAssertNil(IRYUVImageDimensions32(width: 0, height: 4))
        XCTAssertNil(IRYUVImageDimensions32(width: 4, height: 0))
        XCTAssertNil(IRYUVImageDimensions32(width: Int.max, height: 4))
        XCTAssertNil(IRYUVImageDimensions32(width: 4, height: Int.max))
    }

    func testYUVImageDimensions32ConvertsValidDimensions() {
        let dimensions = IRYUVImageDimensions32(width: 640, height: 480)

        XCTAssertEqual(dimensions?.width, 640)
        XCTAssertEqual(dimensions?.height, 480)
    }
}
