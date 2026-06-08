import Foundation

enum IRFFPlayerPlaybackPolicy {

    static func replaceVideoReadiness(hasAbstractPlayer: Bool,
                                      hasContentURL: Bool,
                                      hasDisplayView: Bool) -> IRFFPlayer.ReplaceVideoReadiness {
        guard hasAbstractPlayer, hasContentURL else { return .missingRequiredInput }
        guard hasDisplayView else { return .missingDisplayView }
        return .ready
    }

    static func playTransition(from state: IRPlayerState) -> IRFFPlayer.PlayTransition {
        switch state {
        case .finished:
            return IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: true)
        case .none, .failed, .buffering:
            return IRFFPlayer.PlayTransition(nextState: .buffering, shouldSeekToStart: false)
        case .readyToPlay, .playing, .suspend:
            return IRFFPlayer.PlayTransition(nextState: .playing, shouldSeekToStart: false)
        }
    }

    static func pauseTransition(from state: IRPlayerState) -> IRPlayerState? {
        switch state {
        case .none, .suspend:
            return nil
        case .failed, .readyToPlay, .finished, .playing, .buffering:
            return .suspend
        }
    }

    static func bufferingTransition(isBuffering: Bool,
                                    isPlaying: Bool,
                                    hasPreparedOnce: Bool) -> IRFFPlayer.BufferingTransition {
        guard !isBuffering else {
            return IRFFPlayer.BufferingTransition(nextState: .buffering, hasPreparedOnce: hasPreparedOnce)
        }

        if isPlaying {
            return IRFFPlayer.BufferingTransition(nextState: .playing, hasPreparedOnce: hasPreparedOnce)
        }

        if !hasPreparedOnce {
            return IRFFPlayer.BufferingTransition(nextState: .readyToPlay, hasPreparedOnce: true)
        }

        return IRFFPlayer.BufferingTransition(nextState: .suspend, hasPreparedOnce: hasPreparedOnce)
    }

    static func audioSilenceByteCount(numberOfFrames: UInt32, numberOfChannels: UInt32) -> Int? {
        guard numberOfFrames > 0, numberOfChannels > 0 else { return nil }

        let (sampleCount, sampleCountOverflow) = Int(numberOfFrames).multipliedReportingOverflow(by: Int(numberOfChannels))
        guard !sampleCountOverflow, sampleCount > 0 else { return nil }

        let (byteCount, byteCountOverflow) = sampleCount.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !byteCountOverflow else { return nil }
        return byteCount
    }

    static func audioCopyPlan(frameSize: Int,
                              outputOffset: Int,
                              remainingFrames: UInt32,
                              numberOfChannels: UInt32) -> IRFFPlayer.AudioCopyPlan? {
        guard frameSize > 0,
              outputOffset >= 0,
              outputOffset <= frameSize,
              remainingFrames > 0,
              numberOfChannels > 0 else {
            return nil
        }

        let (frameSizeOf, frameSizeOverflow) = Int(numberOfChannels).multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !frameSizeOverflow, frameSizeOf > 0 else { return nil }
        guard outputOffset % frameSizeOf == 0 else { return nil }

        let bytesLeft = frameSize - outputOffset
        guard bytesLeft > 0 else { return nil }

        let (requestedBytes, requestedBytesOverflow) = Int(remainingFrames).multipliedReportingOverflow(by: frameSizeOf)
        guard !requestedBytesOverflow else { return nil }

        let boundedBytesToCopy = min(requestedBytes, bytesLeft)
        let bytesToCopy = boundedBytesToCopy - (boundedBytesToCopy % frameSizeOf)
        let framesToCopy = bytesToCopy / frameSizeOf
        guard bytesToCopy > 0, framesToCopy > 0 else { return nil }

        return IRFFPlayer.AudioCopyPlan(
            bytesToCopy: bytesToCopy,
            framesToCopy: framesToCopy,
            hasRemainingFrameBytes: bytesToCopy < bytesLeft
        )
    }
}
