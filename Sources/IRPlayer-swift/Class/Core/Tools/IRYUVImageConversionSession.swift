//
//  IRYUVImageConversionSession.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/24.
//

import Foundation
import IRFFMpeg

struct IRYUVImageConversionConfiguration: Equatable {
    let width: Int32
    let height: Int32
    let outputLineSize: Int32
    let outputByteCount: Int

    init?(width: Int, height: Int) {
        guard width > 0,
              height > 0,
              width <= Int(Int32.max),
              height <= Int(Int32.max) else {
            return nil
        }

        let (lineSize, lineSizeOverflow) =
            width.multipliedReportingOverflow(by: 3)
        guard !lineSizeOverflow,
              lineSize > 0,
              lineSize <= Int(Int32.max) else {
            return nil
        }

        let (byteCount, byteCountOverflow) =
            lineSize.multipliedReportingOverflow(by: height)
        guard !byteCountOverflow, byteCount > 0 else {
            return nil
        }

        self.width = Int32(width)
        self.height = Int32(height)
        outputLineSize = Int32(lineSize)
        outputByteCount = byteCount
    }
}

enum IRYUVImageConversionOutcome: Equatable {
    case converted
    case invalidSource
    case scaleFailed(Int32)
    case incompleteOutput(expected: Int32, actual: Int32)
    case consumerRejected
    case closed
}

struct IRYUVImageConversionDiagnostics: Equatable {
    let isClosed: Bool
    let hasContext: Bool
    let outputCapacity: Int
}

struct IRYUVImageConversionRuntime {
    let makeContext: (
        IRYUVImageConversionConfiguration,
        AVPixelFormat
    ) -> OpaquePointer?
    let allocateOutput: (Int) -> [UInt8]?
    let scale: (
        OpaquePointer,
        [UnsafePointer<UInt8>?],
        [Int32],
        IRYUVImageConversionConfiguration,
        UnsafeMutablePointer<UInt8>
    ) -> Int32
    let freeContext: (inout OpaquePointer?) -> Void

    static let live = IRYUVImageConversionRuntime(
        makeContext: {
            configuration,
            sourcePixelFormat in
            sws_getCachedContext(
                nil,
                configuration.width,
                configuration.height,
                sourcePixelFormat,
                configuration.width,
                configuration.height,
                AV_PIX_FMT_RGB24,
                1,
                nil,
                nil,
                nil
            )
        },
        allocateOutput: { byteCount in
            guard byteCount > 0 else { return nil }
            return [UInt8](
                repeating: 0,
                count: byteCount
            )
        },
        scale: {
            context,
            sourceData,
            sourceLineSizes,
            configuration,
            output in
            let pointerCount = Int(AV_NUM_DATA_POINTERS)
            var normalizedSourceData = Array(
                sourceData.prefix(pointerCount)
            )
            var normalizedSourceLineSizes = Array(
                sourceLineSizes.prefix(pointerCount)
            )
            normalizedSourceData.append(
                contentsOf: repeatElement(
                    nil,
                    count: pointerCount
                        - normalizedSourceData.count
                )
            )
            normalizedSourceLineSizes.append(
                contentsOf: repeatElement(
                    0,
                    count: pointerCount
                        - normalizedSourceLineSizes.count
                )
            )

            var destinationData =
                [UnsafeMutablePointer<UInt8>?](
                    repeating: nil,
                    count: pointerCount
                )
            var destinationLineSizes = [Int32](
                repeating: 0,
                count: pointerCount
            )
            destinationData[0] = output
            destinationLineSizes[0] =
                configuration.outputLineSize

            return sws_scale(
                context,
                normalizedSourceData,
                normalizedSourceLineSizes,
                0,
                configuration.height,
                &destinationData,
                &destinationLineSizes
            )
        },
        freeContext: { context in
            guard let ownedContext = context else { return }
            sws_freeContext(ownedContext)
            context = nil
        }
    )
}

final class IRYUVImageConversionSession:
    @unchecked Sendable
{
    let configuration: IRYUVImageConversionConfiguration

    private let runtime: IRYUVImageConversionRuntime
    private let lock = NSLock()
    private var context: OpaquePointer?
    private var output: [UInt8]
    private var isClosed = false

    init?(
        width: Int,
        height: Int,
        sourcePixelFormat: AVPixelFormat,
        runtime: IRYUVImageConversionRuntime = .live
    ) {
        guard let configuration =
                IRYUVImageConversionConfiguration(
                    width: width,
                    height: height
                ),
              let context = runtime.makeContext(
                  configuration,
                  sourcePixelFormat
              ) else {
            return nil
        }

        guard let output = runtime.allocateOutput(
            configuration.outputByteCount
        ),
        output.count >= configuration.outputByteCount else {
            var partialContext: OpaquePointer? = context
            runtime.freeContext(&partialContext)
            return nil
        }

        self.configuration = configuration
        self.runtime = runtime
        self.context = context
        self.output = output
    }

    deinit {
        close()
    }

    var diagnostics: IRYUVImageConversionDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return IRYUVImageConversionDiagnostics(
            isClosed: isClosed,
            hasContext: context != nil,
            outputCapacity: output.count
        )
    }

    @discardableResult
    func withConvertedRGB(
        sourceData: [UnsafePointer<UInt8>?],
        sourceLineSizes: [Int32],
        _ body: (
            UnsafeBufferPointer<UInt8>,
            IRYUVImageConversionConfiguration
        ) -> Bool
    ) -> IRYUVImageConversionOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, let context else {
            return .closed
        }
        guard IRYUVSourcePlaneInputsAreValid(
            srcData: sourceData,
            srcLinesize: sourceLineSizes
        ) else {
            return .invalidSource
        }
        guard output.count >=
                configuration.outputByteCount else {
            return .consumerRejected
        }

        return output.withUnsafeMutableBufferPointer {
            outputBuffer in
            guard let outputBase = outputBuffer.baseAddress else {
                return .consumerRejected
            }

            let scaledHeight = runtime.scale(
                context,
                sourceData,
                sourceLineSizes,
                configuration,
                outputBase
            )
            guard scaledHeight >= 0 else {
                return .scaleFailed(scaledHeight)
            }
            guard scaledHeight == configuration.height else {
                return .incompleteOutput(
                    expected: configuration.height,
                    actual: scaledHeight
                )
            }

            let convertedBytes = UnsafeBufferPointer(
                start: UnsafePointer(outputBase),
                count: configuration.outputByteCount
            )
            return body(
                convertedBytes,
                configuration
            ) ? .converted : .consumerRejected
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }

        isClosed = true
        runtime.freeContext(&context)
        output.removeAll(keepingCapacity: false)
    }
}
