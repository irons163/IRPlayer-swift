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

    override var type: IRFFFrameType {
        return .avyuvVideo
    }

    func setFrameData(_ frame: UnsafePointer<AVFrame>, width: Int, height: Int) {
        self.pixelFormat = AVPixelFormat(rawValue: frame.pointee.format)

        self.width = width
        self.height = height

        let linesizeY = frame.pointee.linesize.0
        let linesizeU = frame.pointee.linesize.1
        let linesizeV = frame.pointee.linesize.2

        channelLinesize[IRYUVChannel.luma.rawValue] = Int32(linesizeY)
        channelLinesize[IRYUVChannel.chromaB.rawValue] = Int32(linesizeU)
        channelLinesize[IRYUVChannel.chromaR.rawValue] = Int32(linesizeV)

        updateChannelBuffer(for: .luma, width: width, height: height, linesize: linesizeY)
        updateChannelBuffer(for: .chromaB, width: width / 2, height: height / 2, linesize: linesizeU)
        updateChannelBuffer(for: .chromaR, width: width / 2, height: height / 2, linesize: linesizeV)

        copyFrameData(frame.pointee.data.0!, to: &channelPixels[IRYUVChannel.luma.rawValue], linesize: linesizeY, width: width, height: height)
        copyFrameData(frame.pointee.data.1!, to: &channelPixels[IRYUVChannel.chromaB.rawValue], linesize: linesizeU, width: width / 2, height: height / 2)
        copyFrameData(frame.pointee.data.2!, to: &channelPixels[IRYUVChannel.chromaR.rawValue], linesize: linesizeV, width: width / 2, height: height / 2)
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
    }

    override func stopPlaying() {
        lock.lock()
        super.stopPlaying()
        lock.unlock()
    }

    func image() -> IRPLFImage {
        lock.lock()
        let image = IRYUVConvertToImage(srcData: channelPixels, srcLinesize: channelLinesize, width: width, height: height, pixelFormat: pixelFormat!)!
        lock.unlock()
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
    return width * height
}

func IRYUVChannelFilter(_ source: UnsafePointer<UInt8>, _ linesize: Int32, _ width: Int, _ height: Int, _ destination: UnsafeMutablePointer<UInt8>?, _ bufferSize: Int, _ a: Int) {
    guard let destination = destination else { return }

    let linesize = Int(linesize)
    for y in 0..<height {
        let srcRow = source + y * linesize
        let dstRow = destination + y * width
        memcpy(dstRow, srcRow, width)
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
