import CoreVideo
import IRFFMpeg
import XCTest
@testable import IRPlayer_swift

final class IRFFAVYUVVideoFrameTests: XCTestCase {

    private func makePixelBuffer(width: Int = 3,
                                 height: Int = 5,
                                 format: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable")
        }
        return pixelBuffer
    }

    func testImageReturnsNilWhenFrameDataIsMissing() {
        let frame = IRFFAVYUVVideoFrame()

        let image: IRPLFImage? = frame.image()

        XCTAssertNil(image)
    }

    func testCVYUVVideoFrameUsesPixelBufferDimensionsAndType() throws {
        let pixelBuffer = try makePixelBuffer(width: 3, height: 5)

        let frame = IRFFCVYUVVideoFrame(pixelBuffer: pixelBuffer)

        XCTAssertEqual(frame.type, .cvyuvVideo)
        XCTAssertEqual(frame.width, 3)
        XCTAssertEqual(frame.height, 5)
        XCTAssertTrue(frame.pixelBuffer === pixelBuffer)
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

    func testChannelBufferSizeUsesRequestedPlaneCapacity() {
        let capacities = [16, 4, 5]

        XCTAssertEqual(IRFFAVYUVVideoFrame.channelBufferSize(for: .luma, capacities: capacities), 16)
        XCTAssertEqual(IRFFAVYUVVideoFrame.channelBufferSize(for: .chromaB, capacities: capacities), 4)
        XCTAssertEqual(IRFFAVYUVVideoFrame.channelBufferSize(for: .chromaR, capacities: capacities), 5)
        XCTAssertNil(IRFFAVYUVVideoFrame.channelBufferSize(for: .count, capacities: capacities))
        XCTAssertNil(IRFFAVYUVVideoFrame.channelBufferSize(for: .chromaR, capacities: [16, 4]))
    }

    func testYUVChannelFilterNeedSizeCheckedRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 0, height: 4, channelCount: 1))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 4, height: 0, channelCount: 1))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 4, height: 4, channelCount: 0))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: .max, width: .max, height: 2, channelCount: 2))
        XCTAssertNil(IRYUVChannelFilterNeedSizeChecked(linesize: .max, width: .max, height: 2, channelCount: 1))
    }

    func testYUVChannelFilterNeedSizeCheckedUsesAdjustedWidth() {
        XCTAssertEqual(IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 8, height: 3, channelCount: 2), 24)
    }

    func testYUVToolsWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRYUVChannelFilterNeedSizeChecked(linesize: 4, width: 8, height: 3, channelCount: 2),
            IRYUVToolsPolicy.channelFilterNeedSizeChecked(linesize: 4, width: 8, height: 3, channelCount: 2)
        )
        XCTAssertEqual(
            IRYUVChannelFilterNeedSize(linesize: 4, width: 8, height: 3, channelCount: 2),
            IRYUVToolsPolicy.channelFilterNeedSize(linesize: 4, width: 8, height: 3, channelCount: 2)
        )
        XCTAssertEqual(
            IRYUVImageDimensions32(width: 640, height: 480)?.width,
            IRYUVToolsPolicy.imageDimensions32(width: 640, height: 480)?.width
        )
        XCTAssertEqual(
            IRYUVImageDimensions32(width: 640, height: 480)?.height,
            IRYUVToolsPolicy.imageDimensions32(width: 640, height: 480)?.height
        )
        XCTAssertNil(IRYUVToolsPolicy.imageDimensions32(width: 0, height: 480))
    }

    func testYUVToolsPolicyChannelFilterCopiesAdjustedRowsAndClearsDestination() {
        var source: [UInt8] = [
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12
        ]
        var destination = [UInt8](repeating: 0xff, count: 6)

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVToolsPolicy.channelFilter(
                    src: sourceBuffer.baseAddress!,
                    linesize: 4,
                    width: 2,
                    height: 3,
                    dst: destinationBuffer.baseAddress!,
                    dstsize: destinationBuffer.count,
                    channelCount: 1
                )
            }
        }

        XCTAssertEqual(destination, [1, 2, 5, 6, 9, 10])
    }

    func testYUVToolsPolicyChannelFilterLeavesDestinationZeroedWhenOutputIsTooSmall() {
        var source = [UInt8](1...8)
        var destination = [UInt8](repeating: 0xff, count: 3)

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVToolsPolicy.channelFilter(
                    src: sourceBuffer.baseAddress!,
                    linesize: 4,
                    width: 2,
                    height: 2,
                    dst: destinationBuffer.baseAddress!,
                    dstsize: destinationBuffer.count,
                    channelCount: 1
                )
            }
        }

        XCTAssertEqual(destination, [0, 0, 0])
    }

    func testYUVChannelFilterWrappersRemainSourceCompatible() {
        XCTAssertEqual(
            IRYUVChannelFilterNeedSize(4, 8, 3, 2),
            IRYUVChannelFilterPolicy.needSize(linesize: 4, width: 8, height: 3, channelCount: 2)
        )
        XCTAssertEqual(
            IRYUVChannelFilterNeedSize(-1, 8, 3, 2),
            IRYUVChannelFilterPolicy.needSize(linesize: -1, width: 8, height: 3, channelCount: 2)
        )

        var source = [UInt8](1...8)
        var destination = [UInt8](repeating: 0, count: 4)
        let destinationCount = destination.count
        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(sourceBuffer.baseAddress!, 4, 2, 2, destinationBuffer.baseAddress, destinationCount, 1)
            }
        }

        XCTAssertEqual(destination, [1, 2, 5, 6])
    }

    func testYUVChannelFilterIgnoresMissingOrTooSmallDestination() {
        var source = [UInt8](1...8)
        var destination = [UInt8](repeating: 9, count: 3)
        let destinationCount = destination.count
        source.withUnsafeMutableBufferPointer { sourceBuffer in
            IRYUVChannelFilter(sourceBuffer.baseAddress!, 4, 2, 2, nil, 4, 1)

            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(sourceBuffer.baseAddress!, 4, 2, 2, destinationBuffer.baseAddress, destinationCount, 1)
            }
        }

        XCTAssertEqual(destination, [9, 9, 9])
    }

    func testYUVConvertToImageRejectsInvalidDimensions() {
        var source = [UInt8](repeating: 0, count: 3)
        let image = source.withUnsafeMutableBufferPointer { sourceBuffer in
            IRYUVConvertToImage(
                srcData: [UnsafePointer(sourceBuffer.baseAddress!)],
                srcLinesize: [3],
                width: 0,
                height: 1,
                pixelFormat: AV_PIX_FMT_RGB24
            )
        }

        XCTAssertNil(image)
    }

    func testYUVConvertToImageBuildsImageFromRGB24Data() throws {
        var source: [UInt8] = [
            255, 0, 0, 0, 255, 0,
            0, 0, 255, 255, 255, 255
        ]
        let image = source.withUnsafeMutableBufferPointer { sourceBuffer in
            IRYUVConvertToImage(
                srcData: [UnsafePointer(sourceBuffer.baseAddress!)],
                srcLinesize: [6],
                width: 2,
                height: 2,
                pixelFormat: AV_PIX_FMT_RGB24
            )
        }

        let unwrappedImage = try XCTUnwrap(image)
        XCTAssertEqual(unwrappedImage.size.width, 2)
        XCTAssertEqual(unwrappedImage.size.height, 2)
        XCTAssertNotNil(unwrappedImage.cgImage)
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
