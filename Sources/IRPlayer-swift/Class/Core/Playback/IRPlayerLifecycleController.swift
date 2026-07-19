import Foundation

final class IRPlayerLifecycleController {
    enum Command: Equatable {
        case none
        case play
        case pause
    }

    var mode: IRPlayerBackgroundMode
    private(set) var needsForegroundResume = false
    private(set) var lastForegroundTime: TimeInterval?

    init(mode: IRPlayerBackgroundMode = .autoPlayAndPause) {
        self.mode = mode
    }

    func didEnterBackground(state: IRPlayerState) -> Command {
        switch IRPlayerLifecyclePolicy.backgroundAction(mode: mode, state: state) {
        case .pauseAndRememberAutoPlay:
            needsForegroundResume = true
            return .pause
        case .none:
            return .none
        }
    }

    func willEnterForeground(state: IRPlayerState, now: TimeInterval) -> Command {
        switch IRPlayerLifecyclePolicy.foregroundAction(
            mode: mode,
            state: state,
            needAutoPlay: needsForegroundResume
        ) {
        case .playAndClearAutoPlay:
            needsForegroundResume = false
            lastForegroundTime = now
            return .play
        case .none:
            return .none
        }
    }

    func audioInterruption(
        type: IRAudioManagerInterruptionType,
        state: IRPlayerState,
        now: TimeInterval
    ) -> Command {
        let elapsed = now - (lastForegroundTime ?? 0)
        switch IRPlayerLifecyclePolicy.audioInterruptionAction(
            type: type,
            state: state,
            timeSinceForeground: elapsed
        ) {
        case .pause:
            return .pause
        case .none:
            return .none
        }
    }

    func audioRouteChanged(
        reason: IRAudioManagerRouteChangeReason,
        state: IRPlayerState
    ) -> Command {
        switch IRPlayerLifecyclePolicy.audioRouteChangeAction(reason: reason, state: state) {
        case .pause:
            return .pause
        case .none:
            return .none
        }
    }

    func reset() {
        needsForegroundResume = false
        lastForegroundTime = nil
    }
}
