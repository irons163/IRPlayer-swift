//
//  IRVideoFrameRGB.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import CoreGraphics
import Foundation
import UIKit

enum IRFrameFormat: String, Hashable, Equatable, Sendable, RawRepresentable {
    case RGB
}

@objc public enum IRRGBPixelFormat:
    Int,
    Hashable,
    Equatable,
    Sendable,
    RawRepresentable
{
    case rgb24
    case bgra32

    var bytesPerPixel: Int {
        switch self {
        case .rgb24:
            return 3
        case .bgra32:
            return 4
        }
    }
}

enum IRRGBMetalUploadFormat: Equatable, Sendable {
    case rgba8
    case bgra8
}

struct IRRGBFrameLayout: Equatable, Sendable {
    let dimensions: IRFFVideoDimensions
    let pixelFormat: IRRGBPixelFormat
    let bytesPerRow: Int
    let minimumBytesPerRow: Int
    let totalByteCount: Int

    static func make(
        width: Int,
        height: Int,
        pixelFormat: IRRGBPixelFormat,
        bytesPerRow: Int,
        byteCount: Int
    ) -> IRRGBFrameLayout? {
        guard let dimensions = IRFFVideoDimensions.make(
            width: width,
            height: height
        ),
        !dimensions.isEmpty,
        bytesPerRow > 0,
        byteCount >= 0 else {
            return nil
        }

        let (minimumBytesPerRow, rowOverflow) =
            width.multipliedReportingOverflow(
                by: pixelFormat.bytesPerPixel
            )
        guard !rowOverflow,
              minimumBytesPerRow > 0,
              bytesPerRow >= minimumBytesPerRow else {
            return nil
        }

        let (totalByteCount, totalOverflow) =
            bytesPerRow.multipliedReportingOverflow(by: height)
        guard !totalOverflow,
              totalByteCount > 0,
              byteCount >= totalByteCount else {
            return nil
        }

        return IRRGBFrameLayout(
            dimensions: dimensions,
            pixelFormat: pixelFormat,
            bytesPerRow: bytesPerRow,
            minimumBytesPerRow: minimumBytesPerRow,
            totalByteCount: totalByteCount
        )
    }
}

struct IRRGBFrameSnapshot: Equatable, Sendable {
    let layout: IRRGBFrameLayout
    let sourceData: Data
    let metalUploadFormat: IRRGBMetalUploadFormat
    let metalUploadBytesPerRow: Int
    let metalUploadData: Data

    var width: Int {
        layout.dimensions.width
    }

    var height: Int {
        layout.dimensions.height
    }

    var pixelFormat: IRRGBPixelFormat {
        layout.pixelFormat
    }

    var bytesPerRow: Int {
        layout.bytesPerRow
    }

    func withUnsafeMetalUploadBytes<T>(
        _ body: (UnsafeRawBufferPointer) -> T
    ) -> T {
        metalUploadData.withUnsafeBytes(body)
    }
}

private struct IRRGBFrameGeneration {
    let snapshot: IRRGBFrameSnapshot

    static func make(
        width: Int,
        height: Int,
        pixelFormat: IRRGBPixelFormat,
        bytesPerRow: Int,
        data: Data
    ) -> IRRGBFrameGeneration? {
        guard let layout = IRRGBFrameLayout.make(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            bytesPerRow: bytesPerRow,
            byteCount: data.count
        ) else {
            return nil
        }

        let sourceData = Data(
            data.prefix(layout.totalByteCount)
        )
        let upload: (
            format: IRRGBMetalUploadFormat,
            bytesPerRow: Int,
            data: Data
        )
        switch pixelFormat {
        case .rgb24:
            guard let rgba = makeRGBAUpload(
                sourceData: sourceData,
                layout: layout
            ) else {
                return nil
            }
            upload = (
                format: .rgba8,
                bytesPerRow: rgba.bytesPerRow,
                data: rgba.data
            )
        case .bgra32:
            upload = (
                format: .bgra8,
                bytesPerRow: layout.bytesPerRow,
                data: sourceData
            )
        }

        return IRRGBFrameGeneration(
            snapshot: IRRGBFrameSnapshot(
                layout: layout,
                sourceData: sourceData,
                metalUploadFormat: upload.format,
                metalUploadBytesPerRow: upload.bytesPerRow,
                metalUploadData: upload.data
            )
        )
    }

    private static func makeRGBAUpload(
        sourceData: Data,
        layout: IRRGBFrameLayout
    ) -> (bytesPerRow: Int, data: Data)? {
        let (bytesPerRow, rowOverflow) =
            layout.dimensions.width.multipliedReportingOverflow(
                by: 4
            )
        guard !rowOverflow, bytesPerRow > 0 else {
            return nil
        }
        let (byteCount, totalOverflow) =
            bytesPerRow.multipliedReportingOverflow(
                by: layout.dimensions.height
            )
        guard !totalOverflow, byteCount > 0 else {
            return nil
        }

        var output = Data(count: byteCount)
        let converted = sourceData.withUnsafeBytes {
            sourceRaw -> Bool in
            output.withUnsafeMutableBytes {
                outputRaw -> Bool in
                guard let sourceBase = sourceRaw.baseAddress?
                    .assumingMemoryBound(to: UInt8.self),
                    let outputBase = outputRaw.baseAddress?
                    .assumingMemoryBound(to: UInt8.self) else {
                    return false
                }

                for row in 0..<layout.dimensions.height {
                    let sourceRow =
                        sourceBase + row * layout.bytesPerRow
                    let outputRow = outputBase + row * bytesPerRow
                    for column in 0..<layout.dimensions.width {
                        let sourcePixel = sourceRow + column * 3
                        let outputPixel = outputRow + column * 4
                        outputPixel[0] = sourcePixel[0]
                        outputPixel[1] = sourcePixel[1]
                        outputPixel[2] = sourcePixel[2]
                        outputPixel[3] = 255
                    }
                }
                return true
            }
        }
        return converted ? (bytesPerRow, output) : nil
    }
}

@objcMembers public class IRVideoFrameRGB: IRFFVideoFrame {
    public let pixelFormat: IRRGBPixelFormat
    public let bytesPerRow: Int
    public let data: Data

    public var linesize: UInt {
        UInt(bytesPerRow)
    }

    public var rgb: Data {
        data
    }

    private let generation: IRRGBFrameGeneration

    override var type: IRFFFrameType {
        return .video
    }

    var format: IRFrameFormat {
        return .RGB
    }

    public init?(
        width: Int,
        height: Int,
        pixelFormat: IRRGBPixelFormat,
        bytesPerRow: Int,
        data: Data
    ) {
        guard let generation = IRRGBFrameGeneration.make(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            bytesPerRow: bytesPerRow,
            data: data
        ) else {
            return nil
        }
        self.generation = generation
        self.pixelFormat = pixelFormat
        self.bytesPerRow = bytesPerRow
        self.data = generation.snapshot.sourceData
        super.init()
        size = generation.snapshot.layout.totalByteCount
    }

    @nonobjc
    override func dimensionSnapshot() -> IRFFVideoDimensions {
        generation.snapshot.layout.dimensions
    }

    @discardableResult
    public override func setDimensions(
        width: Int,
        height: Int
    ) -> Bool {
        guard let dimensions = IRFFVideoDimensions.make(
            width: width,
            height: height
        ) else {
            return false
        }
        return dimensions == dimensionSnapshot()
    }

    func contentSnapshot() -> IRRGBFrameSnapshot {
        generation.snapshot
    }

    func asImage() -> UIImage? {
        let snapshot = contentSnapshot()
        guard let provider = CGDataProvider(
            data: snapshot.sourceData as CFData
        ),
        let colorSpace = CGColorSpace(
            name: CGColorSpace.sRGB
        ) else {
            return nil
        }

        let bitsPerPixel: Int
        let bitmapInfo: CGBitmapInfo
        switch snapshot.pixelFormat {
        case .rgb24:
            bitsPerPixel = 24
            bitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.none.rawValue
            )
        case .bgra32:
            bitsPerPixel = 32
            bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(
                    rawValue:
                        CGImageAlphaInfo.premultipliedFirst.rawValue
                )
            )
        }

        guard let image = CGImage(
            width: snapshot.width,
            height: snapshot.height,
            bitsPerComponent: 8,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: snapshot.bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
