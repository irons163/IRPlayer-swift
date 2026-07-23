import Foundation

// Internal compatibility adapters keep legacy framework collaborators and tests
// source-compatible. Production backends receive kind-tagged host adapters from
// IRPlayerImp so stale backend events still pass through the active-kind gate.
extension IRPlayerImp: IRGLViewHost {}

// Preserve the public delegate conformance while presentation ownership lives
// in IRPlayerPresentationSession. The facade methods forward to that owner.
extension IRPlayerImp: IRGLViewDelegate {}

extension IRPlayerImp: IRPlaybackBackendHost {
    func playbackBackendDidChangeState(
        previous: IRPlayerState,
        current: IRPlayerState
    ) {
        receiveBackendState(previous: previous, current: current)
    }

    func playbackBackendDidUpdateProgress(
        current: TimeInterval,
        total: TimeInterval
    ) {
        receiveBackendProgress(current: current, total: total)
    }

    func playbackBackendDidUpdatePlayableTime(
        current: TimeInterval,
        total: TimeInterval
    ) {
        receiveBackendPlayableTime(current: current, total: total)
    }

    func playbackBackendDidFail(_ error: IRError) {
        receiveBackendFailure(error)
    }
}
