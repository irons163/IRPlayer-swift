//
//  IRFFVideoInput.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/10.
//

import Foundation

open class IRFFVideoInput: IRFFVideoDecoderDataSource {

    public enum OutputType: Int, Hashable, Equatable, Sendable, RawRepresentable {
        case displayView
        case decoder
    }

    private let outputLock = NSLock()
    private weak var storedVideoOutput:
        IRFFDecoderVideoOutput?

    public var videoOutput: IRFFDecoderVideoOutput? {
        get {
            outputLock.lock()
            defer { outputLock.unlock() }
            return storedVideoOutput
        }
        set {
            outputLock.lock()
            storedVideoOutput = newValue
            outputLock.unlock()
        }
    }

    public let outputType: OutputType

    public init(
        videoOutput: IRFFDecoderVideoOutput? = nil,
        outputType: OutputType = .displayView
    ) {
        storedVideoOutput = videoOutput
        self.outputType = outputType
    }

    open func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> Bool {
        return true
    }

    open func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet: IRFFCompressedVideoPacket
    ) -> IRFFVideoFrame? {
        return nil
    }
}
