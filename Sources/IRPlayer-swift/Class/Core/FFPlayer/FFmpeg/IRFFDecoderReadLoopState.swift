//
//  IRFFDecoderReadLoopState.swift
//  IRPlayer-swift
//
//  Created by Codex on 2026/7/7.
//

import Foundation

enum IRFFDecoderReadLoopState {

    enum Action: Equatable {
        case quit
        case completeSeek(IRFFDecoder.SeekCompletionTransition)
        case sleep(TimeInterval)
        case finishEOF(IRFFDecoder.ReadPacketEOFTransition)
        case routePacket(IRFFDecoder.PacketRoute)
    }

    struct AudioTrackSelectionAction: Equatable {
        let shouldClearSelection: Bool
        let seekTarget: TimeInterval?
    }

    static func exitAction(closed: Bool, hasError: Bool) -> Action? {
        return closed || hasError ? .quit : nil
    }

    static func seekCompletionAction(seeking: Bool, progress: TimeInterval) -> Action? {
        guard let transition = IRFFDecoderSeekPolicy.seekCompletionTransition(
            seeking: seeking,
            progress: progress
        ) else {
            return nil
        }
        return .completeSeek(transition)
    }

    static func audioTrackSelectionAction(selectionPending: Bool,
                                          decoderWasReset: Bool,
                                          hasAudioDecoder: Bool,
                                          playbackFinished: Bool,
                                          audioTimeClock: TimeInterval) -> AudioTrackSelectionAction? {
        guard selectionPending else { return nil }
        let seekTarget = IRFFDecoderSeekPolicy.audioTrackSelectionSeekTarget(
            selectionPending: selectionPending,
            decoderWasReset: decoderWasReset,
            hasAudioDecoder: hasAudioDecoder,
            playbackFinished: playbackFinished,
            audioTimeClock: audioTimeClock
        )
        return AudioTrackSelectionAction(shouldClearSelection: true, seekTarget: seekTarget)
    }

    static func backpressureAction(audioSize: Int,
                                   videoPacketSize: Int,
                                   maxBufferSize: Int = 20 * 1024 * 1024,
                                   paused: Bool) -> Action? {
        guard let interval = IRFFDecoderPacketPolicy.packetBufferBackpressureSleepInterval(
            audioSize: audioSize,
            videoPacketSize: videoPacketSize,
            maxBufferSize: maxBufferSize,
            paused: paused
        ) else {
            return nil
        }
        return .sleep(interval)
    }

    static func eofAction(readFrameResult: Int32?) -> Action? {
        guard let transition = IRFFDecoderPacketPolicy.readPacketEOFTransition(
            readFrameResult: readFrameResult
        ) else {
            return nil
        }
        return .finishEOF(transition)
    }

    static func packetAction(streamIndex: Int32,
                             videoTrackIndex: Int?,
                             audioTrackIndex: Int?) -> Action {
        let route = IRFFDecoderPacketPolicy.packetRoute(
            streamIndex: streamIndex,
            videoTrackIndex: videoTrackIndex,
            audioTrackIndex: audioTrackIndex
        )
        return .routePacket(route)
    }
}
