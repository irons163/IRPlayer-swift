//
//  IRFFDecoderReadLoopState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

enum IRFFDecoderReadLoopState {

    enum ReadResult: Equatable {
        case packet
        case retry(after: TimeInterval)
        case endOfStream
        case failed(code: Int32)
    }

    enum Action: Equatable {
        case quit
        case completeSeek(IRFFDecoder.SeekCompletionTransition)
        case sleep(TimeInterval)
        case retryRead(TimeInterval)
        case finishEOF(IRFFDecoder.ReadPacketEOFTransition)
        case failRead(Int32)
        case routePacket(IRFFDecoder.PacketRoute)
    }

    static func exitAction(closed: Bool, hasError: Bool) -> Action? {
        return closed || hasError ? .quit : nil
    }

    static func seekCompletionAction(seeking: Bool, progress: TimeInterval) -> Action? {
        guard let transition = IRFFDecoder.seekCompletionTransition(
            seeking: seeking,
            progress: progress
        ) else {
            return nil
        }
        return .completeSeek(transition)
    }

    static func backpressureAction(audioSize: Int,
                                   videoPacketSize: Int,
                                   maxBufferSize: Int = 20 * 1024 * 1024,
                                   paused: Bool) -> Action? {
        guard let interval =
                IRFFDecoder.packetBufferBackpressureSleepInterval(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            maxBufferSize: maxBufferSize,
            paused: paused
        ) else {
            return nil
        }
        return .sleep(interval)
    }

    static func classifyReadResult(
        _ result: Int32,
        retryAttempt: Int = 0
    ) -> ReadResult {
        if result >= 0 {
            return .packet
        }
        if result == AVERROR(EAGAIN) {
            return .retry(
                after: retryDelay(
                    attempt: retryAttempt
                )
            )
        }
        if result == IR_AVERROR_EOF {
            return .endOfStream
        }
        return .failed(code: result)
    }

    static func retryDelay(
        attempt: Int,
        base: TimeInterval = 0.002,
        maximum: TimeInterval = 0.05
    ) -> TimeInterval {
        guard base.isFinite,
              maximum.isFinite,
              base > 0,
              maximum >= base else {
            return 0.002
        }
        let exponent = min(max(0, attempt), 8)
        let multiplier =
            TimeInterval(1 << exponent)
        return min(maximum, base * multiplier)
    }

    static func readAction(
        readFrameResult: Int32,
        retryAttempt: Int = 0
    ) -> Action? {
        switch classifyReadResult(
            readFrameResult,
            retryAttempt: retryAttempt
        ) {
        case .packet:
            return nil
        case let .retry(after: interval):
            return .retryRead(interval)
        case .endOfStream:
            return .finishEOF(
                IRFFDecoder.ReadPacketEOFTransition(
                    endOfFile: true,
                    videoEndOfFile: true,
                    shouldFinishReadLoop: true,
                    shouldNotifyDelegate: true
                )
            )
        case let .failed(code: code):
            return .failRead(code)
        }
    }

    static func eofAction(
        readFrameResult: Int32?
    ) -> Action? {
        guard let readFrameResult,
              case .endOfStream =
                classifyReadResult(readFrameResult) else {
            return nil
        }
        return readAction(
            readFrameResult: readFrameResult
        )
    }

    static func packetAction(streamIndex: Int32,
                             videoTrackIndex: Int?,
                             audioTrackIndex: Int?) -> Action {
        let route = IRFFDecoder.packetRoute(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
        return .routePacket(route)
    }
}
