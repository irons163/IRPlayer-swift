//
//  IRVideoFrameRGBTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/6/2.
//

import CoreVideo
import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

private final class IRVideoDimensionFailureRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedFailures = 0

    var failures: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFailures
    }

    func recordFailure() {
        lock.lock()
        storedFailures += 1
        lock.unlock()
    }
}

final class IRVideoFrameRGBTests: XCTestCase {
    private func makePixelBuffer(
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferIOSurfacePropertiesKey
                    as String: [:]
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable: \(status)")
        }
        return pixelBuffer
    }

    func testBaseVideoFrameDefaultsToEmptyDimensions() {
        let frame = IRFFVideoFrame()

        XCTAssertEqual(frame.type, .video)
        XCTAssertEqual(frame.dimensionSnapshot(), .zero)
        XCTAssertEqual(frame.width, 0)
        XCTAssertEqual(frame.height, 0)
    }

    func testGenericDimensionsReplaceAtomicallyAndRejectInvalidPairs() {
        let frame = IRFFVideoFrame()

        XCTAssertFalse(frame.setDimensions(width: -1, height: 1))
        XCTAssertFalse(frame.setDimensions(width: 1, height: -1))
        XCTAssertFalse(frame.setDimensions(width: 0, height: 1))
        XCTAssertFalse(frame.setDimensions(width: 1, height: 0))
        XCTAssertEqual(frame.dimensionSnapshot(), .zero)

        XCTAssertTrue(
            frame.setDimensions(width: 640, height: 360)
        )
        XCTAssertEqual(
            frame.dimensionSnapshot(),
            IRFFVideoDimensions.make(
                width: 640,
                height: 360
            )!
        )

        XCTAssertTrue(frame.setDimensions(width: 0, height: 0))
        XCTAssertEqual(frame.dimensionSnapshot(), .zero)
    }

    func testPrepareForReuseClearsGenericDimensions() {
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 640, height: 360)
        )

        frame.prepareForReuse()

        XCTAssertEqual(frame.dimensionSnapshot(), .zero)
    }

    func testConcurrentDimensionUpdatesNeverPublishTornPairs() {
        let frame = IRFFVideoFrame()
        let failures = IRVideoDimensionFailureRecorder()
        let valid = Set([
            IRFFVideoDimensions.zero,
            IRFFVideoDimensions.make(
                width: 640,
                height: 360
            )!,
            IRFFVideoDimensions.make(
                width: 1920,
                height: 1080
            )!
        ])

        DispatchQueue.concurrentPerform(iterations: 1_000) {
            index in
            if index.isMultiple(of: 3) {
                _ = frame.setDimensions(
                    width: 640,
                    height: 360
                )
            } else if index.isMultiple(of: 2) {
                _ = frame.setDimensions(
                    width: 1920,
                    height: 1080
                )
            } else if !valid.contains(
                frame.dimensionSnapshot()
            ) {
                failures.recordFailure()
            }
        }

        XCTAssertEqual(failures.failures, 0)
        XCTAssertTrue(valid.contains(frame.dimensionSnapshot()))
    }

    func testCoreVideoFrameOwnsDimensionsAndRejectsReplacement()
        throws {
        let frame = IRFFCVYUVVideoFrame(
            pixelBuffer: try makePixelBuffer(
                width: 7,
                height: 5
            )
        )

        XCTAssertEqual(
            frame.dimensionSnapshot(),
            IRFFVideoDimensions.make(width: 7, height: 5)!
        )
        XCTAssertTrue(frame.setDimensions(width: 7, height: 5))
        XCTAssertFalse(frame.setDimensions(width: 5, height: 7))
        XCTAssertEqual(frame.width, 7)
        XCTAssertEqual(frame.height, 5)
    }

    func testFramePublishesOneCompleteRGB24Generation() throws {
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 2,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 6,
                data: Data([1, 2, 3, 4, 5, 6])
            )
        )

        XCTAssertEqual(frame.type, .video)
        XCTAssertEqual(frame.format, .RGB)
        XCTAssertEqual(frame.pixelFormat, .rgb24)
        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 1)
        XCTAssertEqual(frame.bytesPerRow, 6)
        XCTAssertEqual(frame.linesize, 6)
        XCTAssertEqual(frame.data, Data([1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(frame.rgb, frame.data)
        XCTAssertEqual(frame.size, 6)
    }

    func testConstructionRejectsInvalidGeometryStrideOverflowAndBytes() {
        XCTAssertNil(
            IRVideoFrameRGB(
                width: 0,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 3,
                data: Data(repeating: 0, count: 3)
            )
        )
        XCTAssertNil(
            IRVideoFrameRGB(
                width: 2,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 5,
                data: Data(repeating: 0, count: 6)
            )
        )
        XCTAssertNil(
            IRVideoFrameRGB(
                width: Int.max,
                height: 2,
                pixelFormat: .bgra32,
                bytesPerRow: Int.max,
                data: Data()
            )
        )
        XCTAssertNil(
            IRVideoFrameRGB(
                width: 1,
                height: Int.max,
                pixelFormat: .bgra32,
                bytesPerRow: 4,
                data: Data()
            )
        )
        XCTAssertNil(
            IRVideoFrameRGB(
                width: 2,
                height: 2,
                pixelFormat: .bgra32,
                bytesPerRow: 8,
                data: Data(repeating: 0, count: 15)
            )
        )
    }

    func testGenerationKeepsExactValidatedPrefix() throws {
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 3,
                data: Data([1, 2, 3, 99, 100])
            )
        )

        XCTAssertEqual(frame.data, Data([1, 2, 3]))
        XCTAssertEqual(
            frame.contentSnapshot().layout.totalByteCount,
            3
        )
    }

    func testCallerMutationCannotChangePublishedBytes() throws {
        var input = Data([1, 2, 3])
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 3,
                data: input
            )
        )

        input[0] = 99

        XCTAssertEqual(frame.data, Data([1, 2, 3]))
        XCTAssertEqual(
            frame.contentSnapshot().metalUploadData,
            Data([1, 2, 3, 255])
        )
    }

    func testPaddedRGB24RowsConvertExactlyToPackedRGBA8()
        throws {
        let source = Data([
            1, 2, 3, 4, 5, 6, 90, 91,
            7, 8, 9, 10, 11, 12, 92, 93
        ])
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 2,
                height: 2,
                pixelFormat: .rgb24,
                bytesPerRow: 8,
                data: source
            )
        )
        let snapshot = frame.contentSnapshot()

        XCTAssertEqual(snapshot.sourceData, source)
        XCTAssertEqual(snapshot.metalUploadFormat, .rgba8)
        XCTAssertEqual(snapshot.metalUploadBytesPerRow, 8)
        XCTAssertEqual(
            snapshot.metalUploadData,
            Data([
                1, 2, 3, 255, 4, 5, 6, 255,
                7, 8, 9, 255, 10, 11, 12, 255
            ])
        )
    }

    func testPaddedBGRA32RowsRemainUnchangedForMetal() throws {
        let source = Data([
            1, 2, 3, 255, 90, 91,
            4, 5, 6, 255, 92, 93
        ])
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 2,
                pixelFormat: .bgra32,
                bytesPerRow: 6,
                data: source
            )
        )
        let snapshot = frame.contentSnapshot()

        XCTAssertEqual(snapshot.metalUploadFormat, .bgra8)
        XCTAssertEqual(snapshot.metalUploadBytesPerRow, 6)
        XCTAssertEqual(snapshot.metalUploadData, source)
    }

    func testPublishedRGBDimensionsCannotDivergeFromContent()
        throws {
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 2,
                height: 1,
                pixelFormat: .bgra32,
                bytesPerRow: 8,
                data: Data(repeating: 255, count: 8)
            )
        )
        let snapshot = frame.contentSnapshot()

        XCTAssertTrue(frame.setDimensions(width: 2, height: 1))
        XCTAssertFalse(frame.setDimensions(width: 1, height: 2))
        XCTAssertFalse(frame.setDimensions(width: 0, height: 0))
        XCTAssertEqual(frame.contentSnapshot(), snapshot)
        XCTAssertEqual(
            frame.dimensionSnapshot(),
            IRFFVideoDimensions.make(width: 2, height: 1)!
        )
    }

    func testRGB24BuildsMatchingUIKitImage() throws {
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 1,
                pixelFormat: .rgb24,
                bytesPerRow: 3,
                data: Data([255, 0, 0])
            )
        )

        let image = try XCTUnwrap(frame.asImage())
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(image.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(cgImage.bitsPerPixel, 24)
        XCTAssertEqual(cgImage.bytesPerRow, 3)
    }

    func testBGRA32BuildsMatchingUIKitImage() throws {
        let frame = try XCTUnwrap(
            IRVideoFrameRGB(
                width: 1,
                height: 1,
                pixelFormat: .bgra32,
                bytesPerRow: 4,
                data: Data([0, 0, 255, 255])
            )
        )

        let image = try XCTUnwrap(frame.asImage())
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(image.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(cgImage.bitsPerPixel, 32)
        XCTAssertEqual(cgImage.bytesPerRow, 4)
    }
}
