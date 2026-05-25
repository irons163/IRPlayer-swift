//
//  IRFFAVYUVVideoFrame.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/26.
//

import Foundation
import CoreVideo
import IRFFMpeg

@objcMembers public class IRFFAVYUVVideoFrame: IRFFVideoFrame {
    var channelPixels = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: IRYUVChannel.count.rawValue)
    private var pixelFormat: AVPixelFormat?
    private var channelPixelsBufferSize = [Int](repeating: 0, count: IRYUVChannel.count.rawValue)
    private var channelLengths = [Int](repeating: 0, count: IRYUVChannel.count.rawValue)
    private var channelLinesize = [Int32](repeating: 0, count: IRYUVChannel.count.rawValue)
    private let lock = NSLock()
    private var cachedImage: IRPLFImage?
    private var isImageDirty = true

    override var type: IRFFFrameType {
        return .avyuvVideo
    }

    func setFrameData(_ frame: UnsafePointer<AVFrame>, width: Int, height: Int) {
        guard width > 0,
              height > 0,
              let luma = frame.pointee.data.0,
              let chromaB = frame.pointee.data.1,
              let chromaR = frame.pointee.data.2 else {
            flush()
            return
        }

        self.pixelFormat = AVPixelFormat(rawValue: frame.pointee.format)

        self.width = width
        self.height = height

        let linesizeY = frame.pointee.linesize.0
        let linesizeU = frame.pointee.linesize.1
        let linesizeV = frame.pointee.linesize.2
        guard linesizeY > 0, linesizeU > 0, linesizeV > 0 else {
            flush()
            return
        }

        channelLinesize[IRYUVChannel.luma.rawValue] = Int32(linesizeY)
        channelLinesize[IRYUVChannel.chromaB.rawValue] = Int32(linesizeU)
        channelLinesize[IRYUVChannel.chromaR.rawValue] = Int32(linesizeV)

        updateChannelBuffer(for: .luma, width: width, height: height, linesize: linesizeY)
        updateChannelBuffer(for: .chromaB, width: width / 2, height: height / 2, linesize: linesizeU)
        updateChannelBuffer(for: .chromaR, width: width / 2, height: height / 2, linesize: linesizeV)

        copyFrameData(luma, to: &channelPixels[IRYUVChannel.luma.rawValue], linesize: linesizeY, width: width, height: height)
        copyFrameData(chromaB, to: &channelPixels[IRYUVChannel.chromaB.rawValue], linesize: linesizeU, width: width / 2, height: height / 2)
        copyFrameData(chromaR, to: &channelPixels[IRYUVChannel.chromaR.rawValue], linesize: linesizeV, width: width / 2, height: height / 2)
        isImageDirty = true
    }

    public var luma: UnsafeMutablePointer<UInt8>? {
        return channelPixels[IRYUVChannel.luma.rawValue]
    }

    public var chromaB: UnsafeMutablePointer<UInt8>? {
        return channelPixels[IRYUVChannel.chromaB.rawValue]
    }

    public var chromaR: UnsafeMutablePointer<UInt8>? {
        return channelPixels[IRYUVChannel.chromaR.rawValue]
    }

    func flush() {
        width = 0
        height = 0
        for i in 0..<IRYUVChannel.count.rawValue {
            channelLengths[i] = 0
            channelLinesize[i] = 0
            if let pixels = channelPixels[i], channelPixelsBufferSize[i] > 0 {
                memset(pixels, 0, channelPixelsBufferSize[i])
            }
        }
        size = channelLengths.reduce(0, +)
        cachedImage = nil
        isImageDirty = true
    }

    override func stopPlaying() {
        lock.lock()
        super.stopPlaying()
        lock.unlock()
    }

    func image() -> IRPLFImage? {
        lock.lock()
        defer { lock.unlock() }
        if !isImageDirty, let cachedImage {
            return cachedImage
        }
        guard width > 0, height > 0, let pixelFormat else { return nil }
        guard let image = IRYUVConvertToImage(srcData: channelPixels, srcLinesize: channelLinesize, width: width, height: height, pixelFormat: pixelFormat) else { return nil }
        cachedImage = image
        isImageDirty = false
        return image
    }

    deinit {
        for i in 0..<IRYUVChannel.count.rawValue {
            if let pixels = channelPixels[i], channelPixelsBufferSize[i] > 0 {
                free(pixels)
            }
        }
    }

    private func updateChannelBuffer(for channel: IRYUVChannel, width: Int, height: Int, linesize: Int32) {
        let needSize = IRYUVChannelFilterNeedSize(linesize, width, height, 1)
        channelLengths[channel.rawValue] = needSize
        size = channelLengths.reduce(0, +)
        if channelPixelsBufferSize[channel.rawValue] < needSize {
            if channelPixelsBufferSize[channel.rawValue] > 0, let buffer = channelPixels[channel.rawValue] {
                free(buffer)
            }
            channelPixelsBufferSize[channel.rawValue] = needSize
            channelPixels[channel.rawValue] = malloc(needSize)?.assumingMemoryBound(to: UInt8.self)
        }
    }

    private func copyFrameData(_ source: UnsafePointer<UInt8>, to destination: inout UnsafeMutablePointer<UInt8>?, linesize: Int32, width: Int, height: Int) {
        IRYUVChannelFilter(source, linesize, width, height, destination, channelPixelsBufferSize[IRYUVChannel.luma.rawValue], 1)
    }
}

// Mocking external functions and types for completeness
//struct IRPLFImage {}

func IRYUVChannelFilterNeedSize(_ linesize: Int32, _ width: Int, _ height: Int, _ a: Int) -> Int {
    return IRYUVChannelFilterNeedSizeChecked(linesize: Int(linesize), width: width, height: height, channelCount: a) ?? 0
}

func IRYUVChannelFilter(_ source: UnsafePointer<UInt8>, _ linesize: Int32, _ width: Int, _ height: Int, _ destination: UnsafeMutablePointer<UInt8>?, _ bufferSize: Int, _ a: Int) {
    guard let destination = destination else { return }

    let linesize = Int(linesize)
    guard let rowByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: 1, channelCount: a),
          let totalByteCount = IRYUVChannelFilterNeedSizeChecked(linesize: linesize, width: width, height: height, channelCount: a),
          totalByteCount <= bufferSize else { return }

    for y in 0..<height {
        let srcRow = source + y * linesize
        let dstRow = destination + y * rowByteCount
        memcpy(dstRow, srcRow, rowByteCount)
    }
}

//func IRYUVConvertToImage(_ channelPixels: [UnsafeMutablePointer<UInt8>?], _ channelLinesize: [Int], _ width: Int, _ height: Int, _ pixelFormat: AVPixelFormat?) -> IRPLFImage {
//    return IRPLFImage()
//}

//struct AVFrame {
//    var format: Int32
//    var linesize: [Int32]
//    var data: [UnsafePointer<UInt8>?]
//}
