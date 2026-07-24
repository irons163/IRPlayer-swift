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

    private func makeValidAVYUVVideoFrame() -> IRFFAVYUVVideoFrame {
        var y = Array(UInt8(1)...UInt8(16))
        var u = Array(UInt8(21)...UInt8(24))
        var v = Array(UInt8(31)...UInt8(34))
        var avFrame = AVFrame()
        avFrame.format = AV_PIX_FMT_YUV420P.rawValue
        avFrame.linesize.0 = 4
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

        return frame
    }

    private func setYUV420FrameData(on frame: IRFFAVYUVVideoFrame,
                                    width: Int,
                                    height: Int,
                                    format: Int32,
                                    lumaStart: UInt8,
                                    chromaBStart: UInt8,
                                    chromaRStart: UInt8) {
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        var y = (0..<(width * height)).map { UInt8(Int(lumaStart) + $0) }
        var u = (0..<(chromaWidth * chromaHeight)).map { UInt8(Int(chromaBStart) + $0) }
        var v = (0..<(chromaWidth * chromaHeight)).map { UInt8(Int(chromaRStart) + $0) }
        var avFrame = AVFrame()
        avFrame.format = format
        avFrame.linesize.0 = Int32(width)
        avFrame.linesize.1 = Int32(chromaWidth)
        avFrame.linesize.2 = Int32(chromaWidth)

        y.withUnsafeMutableBufferPointer { yBuffer in
            u.withUnsafeMutableBufferPointer { uBuffer in
                v.withUnsafeMutableBufferPointer { vBuffer in
                    avFrame.data.0 = yBuffer.baseAddress
                    avFrame.data.1 = uBuffer.baseAddress
                    avFrame.data.2 = vBuffer.baseAddress
                    withUnsafePointer(to: &avFrame) { pointer in
                        frame.setFrameData(pointer, width: width, height: height)
                    }
                }
            }
        }
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

    func testSetFrameDataCopiesValidYUVPlanesAndFlushRevokesSnapshot() throws {
        let frame = makeValidAVYUVVideoFrame()
        let snapshot = try XCTUnwrap(frame.planeSnapshot())
        let capacities = frame.planeCapacities

        XCTAssertEqual(frame.type, .avyuvVideo)
        XCTAssertEqual(frame.width, 4)
        XCTAssertEqual(frame.height, 4)
        XCTAssertEqual(frame.size, 24)
        XCTAssertEqual(
            snapshot.bytes(for: .luma),
            Array(UInt8(1)...UInt8(16))
        )
        XCTAssertEqual(
            snapshot.bytes(for: .chromaB),
            Array(UInt8(21)...UInt8(24))
        )
        XCTAssertEqual(
            snapshot.bytes(for: .chromaR),
            Array(UInt8(31)...UInt8(34))
        )

        frame.flush()

        XCTAssertEqual(frame.width, 0)
        XCTAssertEqual(frame.height, 0)
        XCTAssertEqual(frame.size, 0)
        XCTAssertNil(frame.planeSnapshot())
        XCTAssertEqual(frame.planeCapacities, capacities)
    }

    func testSetFrameDataGrowsManagedPlaneCapacity() throws {
        let frame = makeValidAVYUVVideoFrame()

        setYUV420FrameData(on: frame,
                           width: 8,
                           height: 4,
                           format: AV_PIX_FMT_YUV420P.rawValue,
                           lumaStart: 101,
                           chromaBStart: 41,
                           chromaRStart: 61)
        let snapshot = try XCTUnwrap(frame.planeSnapshot())

        XCTAssertEqual(frame.width, 8)
        XCTAssertEqual(frame.height, 4)
        XCTAssertEqual(frame.size, 48)
        XCTAssertEqual(
            snapshot.bytes(for: .luma),
            Array(UInt8(101)...UInt8(132))
        )
        XCTAssertEqual(
            snapshot.bytes(for: .chromaB),
            Array(UInt8(41)...UInt8(48))
        )
        XCTAssertEqual(
            snapshot.bytes(for: .chromaR),
            Array(UInt8(61)...UInt8(68))
        )
        XCTAssertEqual(frame.planeCapacities, [32, 8, 8])
    }

    func testSetFrameDataReusesCapacityForSmallerGeneration() throws {
        let frame = IRFFAVYUVVideoFrame()
        setYUV420FrameData(
            on: frame,
            width: 8,
            height: 4,
            format: AV_PIX_FMT_YUV420P.rawValue,
            lumaStart: 1,
            chromaBStart: 41,
            chromaRStart: 61
        )
        let capacities = frame.planeCapacities

        setYUV420FrameData(
            on: frame,
            width: 4,
            height: 2,
            format: AV_PIX_FMT_YUV420P.rawValue,
            lumaStart: 101,
            chromaBStart: 21,
            chromaRStart: 31
        )
        let snapshot = try XCTUnwrap(
            frame.planeSnapshot()
        )

        XCTAssertEqual(frame.planeCapacities, capacities)
        XCTAssertEqual(snapshot.byteCount(for: .luma), 8)
        XCTAssertEqual(snapshot.byteCount(for: .chromaB), 2)
        XCTAssertEqual(snapshot.byteCount(for: .chromaR), 2)
        XCTAssertEqual(
            snapshot.bytes(for: .luma),
            Array(UInt8(101)...UInt8(108))
        )
    }

    func testImageCachesConvertedYUVImageUntilFrameChanges() throws {
        let frame = makeValidAVYUVVideoFrame()

        let firstImage = try XCTUnwrap(frame.image())
        let secondImage = try XCTUnwrap(frame.image())

        XCTAssertTrue(firstImage === secondImage)
        XCTAssertEqual(firstImage.size.width, 4)
        XCTAssertEqual(firstImage.size.height, 4)

        frame.flush()

        XCTAssertNil(frame.image())
    }

    func testPlaneSnapshotRemainsImmutableAcrossLaterFrameUpdate() throws {
        let frame = makeValidAVYUVVideoFrame()
        let first = try XCTUnwrap(frame.planeSnapshot())

        setYUV420FrameData(
            on: frame,
            width: 8,
            height: 4,
            format: AV_PIX_FMT_YUV420P.rawValue,
            lumaStart: 101,
            chromaBStart: 41,
            chromaRStart: 61
        )
        let second = try XCTUnwrap(frame.planeSnapshot())

        XCTAssertGreaterThan(second.generation, first.generation)
        XCTAssertEqual(
            first.bytes(for: .luma),
            Array(UInt8(1)...UInt8(16))
        )
        XCTAssertEqual(
            second.bytes(for: .luma),
            Array(UInt8(101)...UInt8(132))
        )
    }

    func testPlaneSnapshotDoesNotTrustMutableCompatibilityMetadata() throws {
        let frame = makeValidAVYUVVideoFrame()
        frame.width = 1
        frame.height = 1
        frame.size = 1

        let snapshot = try XCTUnwrap(
            frame.planeSnapshot()
        )

        XCTAssertEqual(snapshot.width, 4)
        XCTAssertEqual(snapshot.height, 4)
        XCTAssertEqual(snapshot.chromaWidth, 2)
        XCTAssertEqual(snapshot.chromaHeight, 2)
        XCTAssertEqual(snapshot.totalByteCount, 24)
    }

    func testOddI420FramePublishesCeilingChromaPlanes() throws {
        let frame = IRFFAVYUVVideoFrame()
        setYUV420FrameData(
            on: frame,
            width: 5,
            height: 3,
            format: AV_PIX_FMT_YUV420P.rawValue,
            lumaStart: 1,
            chromaBStart: 21,
            chromaRStart: 31
        )
        let snapshot = try XCTUnwrap(
            frame.planeSnapshot()
        )

        XCTAssertEqual(snapshot.width, 5)
        XCTAssertEqual(snapshot.height, 3)
        XCTAssertEqual(snapshot.chromaWidth, 3)
        XCTAssertEqual(snapshot.chromaHeight, 2)
        XCTAssertEqual(snapshot.byteCount(for: .luma), 15)
        XCTAssertEqual(snapshot.byteCount(for: .chromaB), 6)
        XCTAssertEqual(snapshot.byteCount(for: .chromaR), 6)
        XCTAssertEqual(snapshot.totalByteCount, 27)
        XCTAssertEqual(frame.size, 27)
    }

    func testConcurrentUpdateAndSnapshotRemainGenerationCoherent() {
        let frame = makeValidAVYUVVideoFrame()
        let invalidSnapshots = LockedYUVFrameTestValue(0)

        DispatchQueue.concurrentPerform(iterations: 120) {
            index in
            if index.isMultiple(of: 3) {
                if index.isMultiple(of: 2) {
                    self.setYUV420FrameData(
                        on: frame,
                        width: 4,
                        height: 4,
                        format: AV_PIX_FMT_YUV420P.rawValue,
                        lumaStart: 1,
                        chromaBStart: 21,
                        chromaRStart: 31
                    )
                } else {
                    self.setYUV420FrameData(
                        on: frame,
                        width: 8,
                        height: 4,
                        format: AV_PIX_FMT_YUV420P.rawValue,
                        lumaStart: 101,
                        chromaBStart: 41,
                        chromaRStart: 61
                    )
                }
                return
            }

            guard let snapshot = frame.planeSnapshot(),
                  let luma = snapshot.bytes(for: .luma),
                  let chromaB = snapshot.bytes(
                      for: .chromaB
                  ),
                  let chromaR = snapshot.bytes(
                      for: .chromaR
                  ) else {
                invalidSnapshots.withValue { $0 += 1 }
                return
            }

            let isSmallGeneration =
                snapshot.width == 4
                && snapshot.height == 4
                && luma.count == 16
                && luma.first == 1
                && chromaB == Array(
                    UInt8(21)...UInt8(24)
                )
                && chromaR == Array(
                    UInt8(31)...UInt8(34)
                )
            let isLargeGeneration =
                snapshot.width == 8
                && snapshot.height == 4
                && luma.count == 32
                && luma.first == 101
                && chromaB == Array(
                    UInt8(41)...UInt8(48)
                )
                && chromaR == Array(
                    UInt8(61)...UInt8(68)
                )
            if !isSmallGeneration && !isLargeGeneration {
                invalidSnapshots.withValue { $0 += 1 }
            }
        }

        XCTAssertEqual(invalidSnapshots.value, 0)
    }

    func testStopPlayingClearsPlayingStateAndNotifiesDelegate() {
        let frame = makeValidAVYUVVideoFrame()
        let delegate = AVYUVFrameDelegateSpy()
        frame.delegate = delegate

        frame.startPlaying()
        frame.stopPlaying()

        XCTAssertFalse(frame.playing)
        XCTAssertTrue(delegate.stoppedFrame === frame)
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
        XCTAssertFalse(
            IRFFAVYUVVideoFrame.shouldAcceptFrameData(
                width: 8,
                height: 4,
                hasLuma: true,
                hasChromaB: true,
                hasChromaR: true,
                linesizeY: 7,
                linesizeU: 4,
                linesizeV: 4
            )
        )
    }

    func testI420LayoutUsesCeilingChromaDimensions() throws {
        let layouts = try XCTUnwrap(
            IRYUVPlaneLayout.i420(
                width: 5,
                height: 3,
                linesizeY: 8,
                linesizeU: 4,
                linesizeV: 4
            )
        )

        XCTAssertEqual(layouts.luma.width, 5)
        XCTAssertEqual(layouts.luma.height, 3)
        XCTAssertEqual(layouts.luma.byteCount, 15)
        XCTAssertEqual(layouts.chromaB.width, 3)
        XCTAssertEqual(layouts.chromaB.height, 2)
        XCTAssertEqual(layouts.chromaB.byteCount, 6)
        XCTAssertEqual(layouts.chromaR, layouts.chromaB)
    }

    func testPlaneLayoutRejectsShortLinesizeAndOverflow() {
        XCTAssertNil(
            IRYUVPlaneLayout(
                width: 5,
                height: 3,
                sourceLinesize: 4
            )
        )
        XCTAssertNil(
            IRYUVPlaneLayout(
                width: Int.max,
                height: 2,
                sourceLinesize: Int32.max
            )
        )
    }

    func testPlaneLayoutCopiesPaddedRowsIntoTightManagedStorage() throws {
        let layout = try XCTUnwrap(
            IRYUVPlaneLayout(
                width: 2,
                height: 3,
                sourceLinesize: 4
            )
        )
        let source: [UInt8] = [
            1, 2, 90, 91,
            3, 4, 92, 93,
            5, 6, 94, 95
        ]
        var storage = [UInt8](
            repeating: 0xff,
            count: 2
        )

        let copied = source.withUnsafeBufferPointer {
            sourceBuffer in
            layout.copy(
                from: sourceBuffer.baseAddress!,
                into: &storage
            )
        }

        XCTAssertTrue(copied)
        XCTAssertEqual(storage, [1, 2, 3, 4, 5, 6])
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

    func testYUVToolsExposeCheckedSemantics() {
        XCTAssertEqual(
            IRYUVChannelFilterNeedSizeChecked(
                linesize: 4,
                width: 8,
                height: 3,
                channelCount: 2
            ),
            24
        )
        XCTAssertEqual(
            IRYUVChannelFilterNeedSize(
                linesize: 4,
                width: 8,
                height: 3,
                channelCount: 2
            ),
            24
        )
        XCTAssertEqual(
            IRYUVChannelFilterNeedSize(
                linesize: 0,
                width: 8,
                height: 3,
                channelCount: 2
            ),
            0
        )
        XCTAssertEqual(
            IRYUVImageDimensions32(
                width: 640,
                height: 480
            )?.width,
            640
        )
        XCTAssertEqual(
            IRYUVImageDimensions32(
                width: 640,
                height: 480
            )?.height,
            480
        )
        XCTAssertNil(
            IRYUVImageDimensions32(
                width: 0,
                height: 480
            )
        )
        XCTAssertTrue(
            IRYUVSourcePlaneInputsAreValid(
                srcData: [
                    UnsafePointer<UInt8>(bitPattern: 1)
                ],
                srcLinesize: [3]
            )
        )
    }

    func testYUVChannelFilterCopiesAdjustedRowsAndClearsDestination() {
        var source: [UInt8] = [
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12
        ]
        var destination = [UInt8](repeating: 0xff, count: 6)

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(
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

    func testYUVChannelFilterLeavesDestinationZeroedWhenOutputIsTooSmall() {
        var source = [UInt8](1...8)
        var destination = [UInt8](repeating: 0xff, count: 3)

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(
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

    func testYUVChannelFilterIgnoresZeroSizedDestination() {
        var source = [UInt8](1...4)
        var destination = [UInt8](repeating: 0xff, count: 1)

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(
                    src: sourceBuffer.baseAddress!,
                    linesize: 4,
                    width: 1,
                    height: 1,
                    dst: destinationBuffer.baseAddress!,
                    dstsize: 0,
                    channelCount: 1
                )
            }
        }

        XCTAssertEqual(destination, [0xff])
    }

    func testYUVToolsChannelFilterWrapperCopiesAdjustedRows() {
        var source: [UInt8] = [
            1, 2, 3, 4,
            5, 6, 7, 8
        ]
        var destination = [UInt8](repeating: 0, count: 4)
        let destinationCount = destination.count

        source.withUnsafeMutableBufferPointer { sourceBuffer in
            destination.withUnsafeMutableBufferPointer { destinationBuffer in
                IRYUVChannelFilter(
                    src: sourceBuffer.baseAddress!,
                    linesize: 4,
                    width: 2,
                    height: 2,
                    dst: destinationBuffer.baseAddress!,
                    dstsize: destinationCount,
                    channelCount: 1
                )
            }
        }

        XCTAssertEqual(destination, [1, 2, 5, 6])
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

    func testYUVConvertToImageRejectsInvalidSourcePlaneInputs() {
        XCTAssertFalse(IRYUVSourcePlaneInputsAreValid(srcData: [], srcLinesize: []))
        XCTAssertFalse(IRYUVSourcePlaneInputsAreValid(srcData: [nil], srcLinesize: [3]))
        XCTAssertFalse(IRYUVSourcePlaneInputsAreValid(srcData: [UnsafePointer<UInt8>(bitPattern: 1)], srcLinesize: [0]))
        XCTAssertFalse(IRYUVSourcePlaneInputsAreValid(srcData: [UnsafePointer<UInt8>(bitPattern: 1)], srcLinesize: [3, 3]))

        XCTAssertNil(IRYUVConvertToImage(srcData: [], srcLinesize: [], width: 2, height: 2, pixelFormat: AV_PIX_FMT_RGB24))
        XCTAssertNil(IRYUVConvertToImage(srcData: [nil], srcLinesize: [3], width: 2, height: 2, pixelFormat: AV_PIX_FMT_RGB24))
        XCTAssertNil(IRYUVConvertToImage(srcData: [UnsafePointer<UInt8>(bitPattern: 1)], srcLinesize: [0], width: 2, height: 2, pixelFormat: AV_PIX_FMT_RGB24))
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

private final class AVYUVFrameDelegateSpy: IRFFFrameDelegate {
    private(set) var stoppedFrame: IRFFFrame?

    func frameDidStartPlaying(_ frame: IRFFFrame) {}

    func frameDidStopPlaying(_ frame: IRFFFrame) {
        stoppedFrame = frame
    }

    func frameDidCancel(_ frame: IRFFFrame) {}
}

private final class LockedYUVFrameTestValue<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
