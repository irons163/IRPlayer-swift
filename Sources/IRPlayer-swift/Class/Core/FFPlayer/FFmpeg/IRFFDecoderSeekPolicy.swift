import Foundation

enum IRFFDecoderSeekPolicy {

    static func seekPreparation(requestedTime: TimeInterval,
                                seekEnabled: Bool,
                                hasError: Bool,
                                hasAudio: Bool,
                                seekMinTime: TimeInterval,
                                duration: TimeInterval,
                                minBufferedDuration: TimeInterval) -> IRFFDecoder.SeekPreparation? {
        guard seekEnabled, !hasError else { return nil }

        let tailBufferDuration: TimeInterval = hasAudio ? 8 : 15
        let rawSeekMaxTime = duration - (minBufferedDuration + tailBufferDuration)
        guard let clampedSeekTime = IRPlaybackTimePolicy.clampedSeekTime(
            requested: requestedTime,
            min: seekMinTime,
            max: rawSeekMaxTime
        ) else {
            return nil
        }

        return IRFFDecoder.SeekPreparation(clampedTime: clampedSeekTime)
    }

    static func resumeSeekTarget(playbackFinished: Bool) -> TimeInterval? {
        return playbackFinished ? 0 : nil
    }

    static func seekCompletionTransition(seeking: Bool, progress: TimeInterval) -> IRFFDecoder.SeekCompletionTransition? {
        guard seeking else { return nil }
        return IRFFDecoder.SeekCompletionTransition(
            endOfFile: false,
            playbackFinished: false,
            buffering: true,
            videoPaused: false,
            videoEndOfFile: false,
            seekToTime: 0,
            audioTimeClock: progress,
            shouldClearFrames: true
        )
    }

    static func audioTrackSelectionSeekTarget(selectionPending: Bool,
                                              decoderWasReset: Bool,
                                              hasAudioDecoder: Bool,
                                              playbackFinished: Bool,
                                              audioTimeClock: TimeInterval) -> TimeInterval? {
        guard selectionPending,
              decoderWasReset,
              hasAudioDecoder,
              !playbackFinished else {
            return nil
        }
        return audioTimeClock
    }
}
