//
//  IRFFYUVPlaneStorage.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import IRFFMpeg

struct IRYUVPlaneLayout: Equatable {
    let width: Int
    let height: Int
    let sourceLinesize: Int
    let rowByteCount: Int
    let byteCount: Int
    let sourceByteCount: Int

    init?(
        width: Int,
        height: Int,
        sourceLinesize: Int32
    ) {
        let sourceLinesize = Int(sourceLinesize)
        guard width > 0,
              height > 0,
              width <= Int(Int32.max),
              sourceLinesize >= width,
              let byteCount = Self.checkedProduct(
                  width,
                  height
              ),
              let lastRowOffset = Self.checkedProduct(
                  height - 1,
                  sourceLinesize
              ),
              let sourceByteCount = Self.checkedSum(
                  lastRowOffset,
                  width
              ) else {
            return nil
        }

        self.width = width
        self.height = height
        self.sourceLinesize = sourceLinesize
        rowByteCount = width
        self.byteCount = byteCount
        self.sourceByteCount = sourceByteCount
    }

    static func i420(
        width: Int,
        height: Int,
        linesizeY: Int32,
        linesizeU: Int32,
        linesizeV: Int32
    ) -> (
        luma: IRYUVPlaneLayout,
        chromaB: IRYUVPlaneLayout,
        chromaR: IRYUVPlaneLayout
    )? {
        guard let chromaWidth = halfCeiling(width),
              let chromaHeight = halfCeiling(height),
              let luma = IRYUVPlaneLayout(
                  width: width,
                  height: height,
                  sourceLinesize: linesizeY
              ),
              let chromaB = IRYUVPlaneLayout(
                  width: chromaWidth,
                  height: chromaHeight,
                  sourceLinesize: linesizeU
              ),
              let chromaR = IRYUVPlaneLayout(
                  width: chromaWidth,
                  height: chromaHeight,
                  sourceLinesize: linesizeV
              ) else {
            return nil
        }
        return (luma, chromaB, chromaR)
    }

    @discardableResult
    func copy(
        from source: UnsafePointer<UInt8>,
        into storage: inout [UInt8]
    ) -> Bool {
        if storage.count < byteCount {
            storage = [UInt8](
                repeating: 0,
                count: byteCount
            )
        }

        return storage.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress,
                  destination.count >= byteCount else {
                return false
            }

            for row in 0..<height {
                let sourceOffset = row * sourceLinesize
                let destinationOffset = row * rowByteCount
                memcpy(
                    destinationBase.advanced(
                        by: destinationOffset
                    ),
                    source.advanced(by: sourceOffset),
                    rowByteCount
                )
            }
            return true
        }
    }

    private static func halfCeiling(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        let (adjusted, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { return nil }
        return adjusted / 2
    }

    private static func checkedProduct(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let (value, overflow) = lhs.multipliedReportingOverflow(
            by: rhs
        )
        return !overflow && value >= 0 ? value : nil
    }

    private static func checkedSum(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int? {
        guard lhs >= 0, rhs >= 0 else { return nil }
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return !overflow && value > 0 ? value : nil
    }
}

struct IRFFYUVPlaneSnapshot {
    let generation: UInt64
    let width: Int
    let height: Int
    let chromaWidth: Int
    let chromaHeight: Int
    let pixelFormat: AVPixelFormat

    private let lumaStorage: [UInt8]
    private let chromaBStorage: [UInt8]
    private let chromaRStorage: [UInt8]
    private let lumaByteCount: Int
    private let chromaBByteCount: Int
    private let chromaRByteCount: Int
    private let storedTotalByteCount: Int

    var totalByteCount: Int {
        storedTotalByteCount
    }

    func byteCount(for channel: IRYUVChannel) -> Int? {
        switch channel {
        case .luma:
            return lumaByteCount
        case .chromaB:
            return chromaBByteCount
        case .chromaR:
            return chromaRByteCount
        case .count:
            return nil
        }
    }

    func bytes(for channel: IRYUVChannel) -> [UInt8]? {
        switch channel {
        case .luma:
            return Array(
                lumaStorage.prefix(lumaByteCount)
            )
        case .chromaB:
            return Array(
                chromaBStorage.prefix(chromaBByteCount)
            )
        case .chromaR:
            return Array(
                chromaRStorage.prefix(chromaRByteCount)
            )
        case .count:
            return nil
        }
    }

    @discardableResult
    func withUnsafePlaneBytes(
        _ body: (
            UnsafeRawPointer,
            UnsafeRawPointer,
            UnsafeRawPointer
        ) -> Bool
    ) -> Bool {
        return lumaStorage.withUnsafeBytes { luma in
            guard let lumaBase = luma.baseAddress,
                  luma.count >= lumaByteCount else {
                return false
            }
            return chromaBStorage.withUnsafeBytes {
                chromaB in
                guard let chromaBBase = chromaB.baseAddress,
                      chromaB.count >= chromaBByteCount else {
                    return false
                }
                return chromaRStorage.withUnsafeBytes {
                    chromaR in
                    guard let chromaRBase = chromaR.baseAddress,
                          chromaR.count >= chromaRByteCount else {
                        return false
                    }
                    return body(
                        lumaBase,
                        chromaBBase,
                        chromaRBase
                    )
                }
            }
        }
    }

    func image() -> IRPLFImage? {
        var convertedImage: IRPLFImage?
        let converted = withUnsafePlaneBytes {
            luma,
            chromaB,
            chromaR in
            convertedImage = IRYUVConvertToImage(
                srcData: [
                    luma.assumingMemoryBound(to: UInt8.self),
                    chromaB.assumingMemoryBound(to: UInt8.self),
                    chromaR.assumingMemoryBound(to: UInt8.self)
                ],
                srcLinesize: [
                    Int32(width),
                    Int32(chromaWidth),
                    Int32(chromaWidth)
                ],
                width: width,
                height: height,
                pixelFormat: pixelFormat
            )
            return convertedImage != nil
        }
        return converted ? convertedImage : nil
    }

    fileprivate init?(
        generation: UInt64,
        width: Int,
        height: Int,
        chromaWidth: Int,
        chromaHeight: Int,
        pixelFormat: AVPixelFormat,
        lumaStorage: [UInt8],
        chromaBStorage: [UInt8],
        chromaRStorage: [UInt8],
        lumaByteCount: Int,
        chromaBByteCount: Int,
        chromaRByteCount: Int
    ) {
        let (lumaAndChromaB, firstOverflow) =
            lumaByteCount.addingReportingOverflow(
                chromaBByteCount
            )
        let (totalByteCount, secondOverflow) =
            lumaAndChromaB.addingReportingOverflow(
                chromaRByteCount
            )
        guard !firstOverflow,
              !secondOverflow,
              totalByteCount > 0,
              generation > 0,
              width > 0,
              height > 0,
              chromaWidth > 0,
              chromaHeight > 0,
              lumaByteCount > 0,
              chromaBByteCount > 0,
              chromaRByteCount > 0,
              lumaByteCount <= lumaStorage.count,
              chromaBByteCount <= chromaBStorage.count,
              chromaRByteCount <= chromaRStorage.count else {
            return nil
        }

        self.generation = generation
        self.width = width
        self.height = height
        self.chromaWidth = chromaWidth
        self.chromaHeight = chromaHeight
        self.pixelFormat = pixelFormat
        self.lumaStorage = lumaStorage
        self.chromaBStorage = chromaBStorage
        self.chromaRStorage = chromaRStorage
        self.lumaByteCount = lumaByteCount
        self.chromaBByteCount = chromaBByteCount
        self.chromaRByteCount = chromaRByteCount
        storedTotalByteCount = totalByteCount
    }
}

struct IRFFYUVPlaneStorage {
    private var luma: [UInt8] = []
    private var chromaB: [UInt8] = []
    private var chromaR: [UInt8] = []
    private var lumaByteCount = 0
    private var chromaBByteCount = 0
    private var chromaRByteCount = 0
    private var activeTotalByteCount = 0

    var capacities: [Int] {
        [luma.count, chromaB.count, chromaR.count]
    }

    var totalByteCount: Int {
        activeTotalByteCount
    }

    mutating func update(
        lumaSource: UnsafePointer<UInt8>,
        chromaBSource: UnsafePointer<UInt8>,
        chromaRSource: UnsafePointer<UInt8>,
        layouts: (
            luma: IRYUVPlaneLayout,
            chromaB: IRYUVPlaneLayout,
            chromaR: IRYUVPlaneLayout
        )
    ) -> Bool {
        let (lumaAndChromaB, firstOverflow) =
            layouts.luma.byteCount.addingReportingOverflow(
                layouts.chromaB.byteCount
            )
        let (totalByteCount, secondOverflow) =
            lumaAndChromaB.addingReportingOverflow(
                layouts.chromaR.byteCount
            )
        guard !firstOverflow,
              !secondOverflow,
              totalByteCount > 0,
              layouts.luma.copy(
                  from: lumaSource,
                  into: &luma
              ),
              layouts.chromaB.copy(
                  from: chromaBSource,
                  into: &chromaB
              ),
              layouts.chromaR.copy(
                  from: chromaRSource,
                  into: &chromaR
              ) else {
            deactivate()
            return false
        }

        lumaByteCount = layouts.luma.byteCount
        chromaBByteCount = layouts.chromaB.byteCount
        chromaRByteCount = layouts.chromaR.byteCount
        activeTotalByteCount = totalByteCount
        return true
    }

    mutating func deactivate() {
        lumaByteCount = 0
        chromaBByteCount = 0
        chromaRByteCount = 0
        activeTotalByteCount = 0
    }

    func snapshot(
        generation: UInt64,
        width: Int,
        height: Int,
        chromaWidth: Int,
        chromaHeight: Int,
        pixelFormat: AVPixelFormat
    ) -> IRFFYUVPlaneSnapshot? {
        return IRFFYUVPlaneSnapshot(
            generation: generation,
            width: width,
            height: height,
            chromaWidth: chromaWidth,
            chromaHeight: chromaHeight,
            pixelFormat: pixelFormat,
            lumaStorage: luma,
            chromaBStorage: chromaB,
            chromaRStorage: chromaR,
            lumaByteCount: lumaByteCount,
            chromaBByteCount: chromaBByteCount,
            chromaRByteCount: chromaRByteCount
        )
    }
}
