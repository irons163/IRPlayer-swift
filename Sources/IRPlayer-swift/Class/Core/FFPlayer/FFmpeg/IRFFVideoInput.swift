//
//  IRFFVideoInput.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation
import IRFFMpeg

open class IRFFVideoInput: IRFFVideoDecoderDataSource {

    public enum OutputType {
        case displayView
        case decoder
    }

    public var videoOutput: IRFFDecoderVideoOutput?
    public var outputType: OutputType = .displayView

    public init(videoOutput: IRFFDecoderVideoOutput? = nil, outputType: OutputType = .displayView) {
        self.videoOutput = videoOutput
        self.outputType = outputType
    }

    open func shouldHandle(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> Bool {
        return true
    }

    open func videoDecoder(_ videoDecoder: IRFFVideoDecoderInfo, decodeFrame packet: AVPacket) -> IRFFVideoFrame? {
        return nil
    }
}
