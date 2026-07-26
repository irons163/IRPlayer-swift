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

    /// Forwards one frame through the active bounded output without waiting.
    ///
    /// A `false` result means the target rejected and reclaimed the frame, or
    /// there was no callable target and this input reclaimed it.
    @discardableResult
    public func trySend(
        videoFrame frame: IRFFVideoFrame
    ) -> Bool {
        guard let videoOutput else {
            frame.cancel()
            return false
        }
        if let accepted =
                videoOutput.trySend?(
                    videoFrame: frame
                ) {
            return accepted
        }
        if videoOutput.send?(
            videoFrame: frame
        ) != nil {
            return true
        }
        frame.cancel()
        return false
    }

    @discardableResult
    public func send(
        videoFrame frame: IRFFVideoFrame
    ) -> Bool {
        trySend(videoFrame: frame)
    }

    open func shouldHandle(
        _ videoDecoder: IRFFVideoDecoderInfo,
        packet: IRFFVideoPacketDescriptor
    ) -> Bool {
        // The base input only routes output. Custom decoders opt in by
        // overriding this method; otherwise FFmpeg remains the safe fallback.
        return false
    }

    open func videoDecoder(
        _ videoDecoder: IRFFVideoDecoderInfo,
        decodeFrame packet:
            IRFFCompressedVideoPacket,
        completion:
            IRFFCustomVideoDecodeCompletion
    ) -> IRFFCustomVideoDecodeOutcome {
        return .dropped
    }
}
