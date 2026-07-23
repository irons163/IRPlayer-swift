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

}
