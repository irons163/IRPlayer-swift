import Foundation

struct IRFFPlayerStateMachine {
    struct Transition: Equatable {
        let previous: IRPlayerState
        let current: IRPlayerState
    }

    struct PlayTransition: Equatable {
        let nextState: IRPlayerState
        let shouldSeekToStart: Bool
    }

    struct BufferingTransition: Equatable {
        let nextState: IRPlayerState
        let hasPreparedOnce: Bool
    }

    private(set) var state: IRPlayerState = .none
    private(set) var playRequested = false
    private(set) var hasPreparedOnce = false

    mutating func transition(to newState: IRPlayerState) -> Transition? {
        guard state != newState else { return nil }
        let transition = Transition(previous: state, current: newState)
        state = newState
        return transition
    }

    mutating func beginPlay() -> PlayTransition {
        playRequested = true
        return Self.playTransition(from: state)
    }

    mutating func beginPause() -> Transition? {
        playRequested = false
        guard let nextState = Self.pauseTransition(from: state) else {
            return nil
        }
        return transition(to: nextState)
    }

    mutating func setPlayRequested(_ requested: Bool) {
        playRequested = requested
    }

    mutating func applyBuffering(_ buffering: Bool) -> Transition? {
        let decision = Self.bufferingTransition(
            isBuffering: buffering,
            isPlaying: playRequested,
            hasPreparedOnce: hasPreparedOnce
        )
        hasPreparedOnce = decision.hasPreparedOnce
        return transition(to: decision.nextState)
    }

    mutating func applyPrepared() -> Transition? {
        // Preparation can arrive after a play/pause command or an unbuffered
        // callback. It must not overwrite that newer playback state or intent.
        guard !playRequested,
              state == .none || state == .buffering else {
            return nil
        }
        return transition(to: .readyToPlay)
    }

    mutating func reset() -> Transition? {
        playRequested = false
        hasPreparedOnce = false
        return transition(to: .none)
    }

    mutating func clearSilently() {
        state = .none
        playRequested = false
        hasPreparedOnce = false
    }

    static func playTransition(from state: IRPlayerState) -> PlayTransition {
        switch state {
        case .finished:
            return PlayTransition(
                nextState: .playing,
                shouldSeekToStart: true
            )
        case .none, .failed, .buffering:
            return PlayTransition(
                nextState: .buffering,
                shouldSeekToStart: false
            )
        case .readyToPlay, .playing, .suspend:
            return PlayTransition(
                nextState: .playing,
                shouldSeekToStart: false
            )
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

    static func bufferingTransition(
        isBuffering: Bool,
        isPlaying: Bool,
        hasPreparedOnce: Bool
    ) -> BufferingTransition {
        guard !isBuffering else {
            return BufferingTransition(
                nextState: .buffering,
                hasPreparedOnce: hasPreparedOnce
            )
        }

        if isPlaying {
            return BufferingTransition(
                nextState: .playing,
                hasPreparedOnce: hasPreparedOnce
            )
        }

        if !hasPreparedOnce {
            return BufferingTransition(
                nextState: .readyToPlay,
                hasPreparedOnce: true
            )
        }

        return BufferingTransition(
            nextState: .suspend,
            hasPreparedOnce: true
        )
    }
}
