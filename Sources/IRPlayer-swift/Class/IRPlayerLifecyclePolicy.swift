import Foundation

enum IRPlayerLifecyclePolicy {
    enum BackendTarget: Hashable, Equatable, Sendable {
        case none
        case avPlayer
        case ffmpeg
    }

    struct ReplacementPlan: Hashable, Equatable, Sendable {
        let stopAVPlayer: Bool
        let stopFFPlayer: Bool
        let replaceTarget: BackendTarget
    }

    enum BackgroundAction: Hashable, Equatable, Sendable {
        case none
        case pauseAndRememberAutoPlay
    }

    enum ForegroundAction: Hashable, Equatable, Sendable {
        case none
        case playAndClearAutoPlay
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
}
