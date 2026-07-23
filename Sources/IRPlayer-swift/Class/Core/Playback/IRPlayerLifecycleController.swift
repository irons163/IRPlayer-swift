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
        guard mode == .autoPlayAndPause else { return .none }
        switch state {
        case .playing, .buffering:
            needsForegroundResume = true
            return .pause
        default:
            return .none
        }
    }

    func willEnterForeground(state: IRPlayerState, now: TimeInterval) -> Command {
        guard mode == .autoPlayAndPause,
              state == .suspend,
              needsForegroundResume else {
            return .none
        }
        needsForegroundResume = false
        lastForegroundTime = now
        return .play
    }

    func audioInterruption(
        type: IRAudioManagerInterruptionType,
        state: IRPlayerState,
        now: TimeInterval
    ) -> Command {
        let elapsed = now - (lastForegroundTime ?? 0)
        guard type == .begin, elapsed > 1.5 else {
            return .none
        }
        return commandForActivePlayback(state)
    }

    func audioRouteChanged(
        reason: IRAudioManagerRouteChangeReason,
        state: IRPlayerState
    ) -> Command {
        guard reason == .oldDeviceUnavailable else { return .none }
        return commandForActivePlayback(state)
    }

    func reset() {
        needsForegroundResume = false
        lastForegroundTime = nil
    }

    private func commandForActivePlayback(
        _ state: IRPlayerState
    ) -> Command {
        switch state {
        case .playing, .buffering:
            return .pause
        default:
            return .none
        }
    }
}
