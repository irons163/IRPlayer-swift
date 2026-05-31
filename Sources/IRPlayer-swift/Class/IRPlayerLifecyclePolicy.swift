import Foundation

enum IRPlayerLifecyclePolicy {
    enum BackendTarget: Equatable {
        case none
        case avPlayer
        case ffmpeg
    }

    struct ReplacementPlan: Equatable {
        let stopAVPlayer: Bool
        let stopFFPlayer: Bool
        let replaceTarget: BackendTarget
    }

    enum BackgroundAction: Equatable {
        case none
        case pauseAndRememberAutoPlay
    }

    enum ForegroundAction: Equatable {
        case none
        case playAndClearAutoPlay
    }

    enum AudioSessionAction: Equatable {
        case none
        case pause
    }

    static func commandTarget(for decoderType: IRDecoderType?) -> BackendTarget {
        switch decoderType {
        case .avPlayer:
            return .avPlayer
        case .ffmpeg:
            return .ffmpeg
        case .error, .none:
            return .none
        }
    }

    static func replacementPlan(for decoderType: IRDecoderType?, hasAVPlayer: Bool, hasFFPlayer: Bool) -> ReplacementPlan {
        switch decoderType {
        case .avPlayer:
            return ReplacementPlan(stopAVPlayer: false, stopFFPlayer: hasFFPlayer, replaceTarget: .avPlayer)
        case .ffmpeg:
            return ReplacementPlan(stopAVPlayer: hasAVPlayer, stopFFPlayer: false, replaceTarget: .ffmpeg)
        case .error, .none:
            return ReplacementPlan(stopAVPlayer: hasAVPlayer, stopFFPlayer: hasFFPlayer, replaceTarget: .none)
        }
    }

    static func backgroundAction(mode: IRPlayerBackgroundMode, state: IRPlayerState) -> BackgroundAction {
        guard mode == .autoPlayAndPause else { return .none }
        switch state {
        case .playing, .buffering:
            return .pauseAndRememberAutoPlay
        default:
            return .none
        }
    }

    static func foregroundAction(mode: IRPlayerBackgroundMode, state: IRPlayerState, needAutoPlay: Bool?) -> ForegroundAction {
        guard mode == .autoPlayAndPause else { return .none }
        guard state == .suspend, needAutoPlay == true else { return .none }
        return .playAndClearAutoPlay
    }

    static func audioInterruptionAction(type: IRAudioManagerInterruptionType, state: IRPlayerState, timeSinceForeground: TimeInterval) -> AudioSessionAction {
        guard type == .begin else { return .none }
        guard timeSinceForeground > 1.5 else { return .none }
        return actionForActivePlayback(state)
    }

    static func audioRouteChangeAction(reason: IRAudioManagerRouteChangeReason, state: IRPlayerState) -> AudioSessionAction {
        guard reason == .oldDeviceUnavailable else { return .none }
        return actionForActivePlayback(state)
    }

    private static func actionForActivePlayback(_ state: IRPlayerState) -> AudioSessionAction {
        switch state {
        case .playing, .buffering:
            return .pause
        default:
            return .none
        }
    }
}
