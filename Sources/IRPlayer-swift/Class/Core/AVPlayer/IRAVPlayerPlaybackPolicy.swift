import AVFoundation

enum IRAVPlayerPlaybackPolicy {

    static func itemStatusDecision(status: AVPlayerItem.Status,
                                   currentState: IRPlayerState) -> IRAVPlayer.ItemStatusDecision {
        switch status {
        case .unknown:
            return .buffer

        case .readyToPlay:
            switch currentState {
            case .buffering, .playing:
                return .playIfNeeded
            case .suspend, .finished, .failed:
                return .ignore
            default:
                return .markReady
            }

        case .failed:
            return .fail

        @unknown default:
            return .failUnknown
        }
    }

    static func nextStateAfterPlay(from state: IRPlayerState) -> IRPlayerState? {
        switch state {
        case .none:
            return .buffering
        case .suspend, .readyToPlay:
            return .playing
        default:
            return nil
        }
    }

    static func nextStateAfterPause(from state: IRPlayerState) -> IRPlayerState? {
        guard state != .failed else { return nil }
        return .suspend
    }

    static func shouldRetryPlayAfterDelay(for state: IRPlayerState) -> Bool {
        switch state {
        case .buffering, .playing, .readyToPlay:
            return true
        default:
            return false
        }
    }

    static func isActivePlaybackState(_ state: IRPlayerState) -> Bool {
        switch state {
        case .buffering, .playing:
            return true
        default:
            return false
        }
    }
}
