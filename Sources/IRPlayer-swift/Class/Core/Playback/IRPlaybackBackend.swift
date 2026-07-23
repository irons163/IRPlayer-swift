import CoreGraphics
import Foundation

protocol IRPlaybackBackendHost: AnyObject {
    var contentURL: NSURL? { get }
    var contentHeaders: [String: String]? { get }
    var videoType: IRVideoType { get }
    var videoInput: IRFFVideoInput? { get }
    var decoder: IRPlayerDecoder { get }
    var displayView: IRGLView? { get }
    var manager: IRAudioManager? { get }
    var error: IRError? { get set }
    var volume: CGFloat { get }
    var playableBufferInterval: TimeInterval { get }
    var isLiveStream: Bool { get }

    func playbackBackendDidChangeState(previous: IRPlayerState, current: IRPlayerState)
    func playbackBackendDidUpdateProgress(current: TimeInterval, total: TimeInterval)
    func playbackBackendDidUpdatePlayableTime(current: TimeInterval, total: TimeInterval)
    func playbackBackendDidFail(_ error: IRError)
}

enum IRPlaybackBackendKind: Hashable, Sendable {
    case avFoundation
    case ffmpeg
}

final class IRPlayerStateStore {
    typealias Transition = (previous: IRPlayerState, current: IRPlayerState)

    private let lock = NSLock()
    private var storedState: IRPlayerState

    init(_ initialState: IRPlayerState = .none) {
        storedState = initialState
    }

    var value: IRPlayerState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    func transition(to newState: IRPlayerState) -> Transition? {
        lock.lock()
        defer { lock.unlock() }
        guard storedState != newState else { return nil }

        let transition = Transition(previous: storedState, current: newState)
        storedState = newState
        return transition
    }
}

extension IRPlaybackBackendKind {
    var decoderType: IRDecoderType {
        switch self {
        case .avFoundation:
            return .avPlayer
        case .ffmpeg:
            return .ffmpeg
        }
    }
}

struct IRPlaybackBackendSnapshot: Equatable, Sendable {
    static let empty = IRPlaybackBackendSnapshot(
        state: .none,
        presentationSize: .zero,
        bitrate: 0,
        progress: 0,
        duration: 0,
        playableTime: 0,
        isSeeking: false
    )

    let state: IRPlayerState
    let presentationSize: CGSize
    let bitrate: TimeInterval
    let progress: TimeInterval
    let duration: TimeInterval
    let playableTime: TimeInterval
    let isSeeking: Bool
}

protocol IRPlaybackBackend: AnyObject {
    var kind: IRPlaybackBackendKind { get }
    var state: IRPlayerState { get }
    var presentationSize: CGSize { get }
    var bitrate: TimeInterval { get }
    var progress: TimeInterval { get }
    var duration: TimeInterval { get }
    var playableTime: TimeInterval { get }
    var seeking: Bool { get }
    var decoderVideoOutput: IRFFDecoderVideoOutput? { get }

    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval, completionHandler: ((Bool) -> Void)?)
    func replaceVideo()
    func reloadVolume()
    func reloadPlayableBufferInterval()
}

extension IRPlaybackBackend {
    var snapshot: IRPlaybackBackendSnapshot {
        IRPlaybackBackendSnapshot(
            state: state,
            presentationSize: presentationSize,
            bitrate: bitrate,
            progress: progress,
            duration: duration,
            playableTime: playableTime,
            isSeeking: seeking
        )
    }
}

extension IRAVPlayer: IRPlaybackBackend {
    var kind: IRPlaybackBackendKind { .avFoundation }
    var decoderVideoOutput: IRFFDecoderVideoOutput? { nil }

    func reloadPlayableBufferInterval() {}
}

extension IRFFPlayer: IRPlaybackBackend {
    var kind: IRPlaybackBackendKind { .ffmpeg }
    var decoderVideoOutput: IRFFDecoderVideoOutput? { decoder }
}

extension IRDecoderType {
    var playbackBackendKind: IRPlaybackBackendKind? {
        switch self {
        case .avPlayer:
            return .avFoundation
        case .ffmpeg:
            return .ffmpeg
        case .error:
            return nil
        }
    }
}
