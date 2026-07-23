import CoreGraphics
import Foundation

final class IRPlayerSettingsStore: @unchecked Sendable {
    struct Snapshot {
        let decoder: IRPlayerDecoder
        let videoType: IRVideoType
        let displayMode: IRDisplayMode
        let autoplay: Bool
        let isLiveStream: Bool
        let playableBufferInterval: TimeInterval
        let volume: CGFloat
        let viewAnimationHidden: Bool
        let error: IRError?
    }

    typealias TapAction = (IRPlayerImp, IRPLFView) -> Void

    private let lock = NSLock()
    private var storedDecoder: IRPlayerDecoder
    private var storedVideoType: IRVideoType
    private var storedDisplayMode: IRDisplayMode
    private var storedAutoplay: Bool
    private var storedIsLiveStream: Bool
    private var storedPlayableBufferInterval: TimeInterval
    private var storedVolume: CGFloat
    private var storedViewAnimationHidden: Bool
    private var storedError: IRError?
    private var storedTapAction: TapAction?

    init(
        decoder: IRPlayerDecoder = .defaultDecoder(),
        videoType: IRVideoType = .normal,
        displayMode: IRDisplayMode = .normal,
        autoplay: Bool = false,
        isLiveStream: Bool = false,
        playableBufferInterval: TimeInterval = 2,
        volume: CGFloat = 1,
        viewAnimationHidden: Bool = true
    ) {
        storedDecoder = decoder
        storedVideoType = videoType
        storedDisplayMode = displayMode
        storedAutoplay = autoplay
        storedIsLiveStream = isLiveStream
        storedPlayableBufferInterval =
            IRPlayerConfiguration.normalizedBufferInterval(
                playableBufferInterval
            )
        storedVolume = IRPlayerConfiguration.normalizedVolume(volume)
        storedViewAnimationHidden = viewAnimationHidden
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            decoder: storedDecoder,
            videoType: storedVideoType,
            displayMode: storedDisplayMode,
            autoplay: storedAutoplay,
            isLiveStream: storedIsLiveStream,
            playableBufferInterval: storedPlayableBufferInterval,
            volume: storedVolume,
            viewAnimationHidden: storedViewAnimationHidden,
            error: storedError
        )
    }

    var decoder: IRPlayerDecoder {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDecoder
        }
        set {
            lock.lock()
            storedDecoder = newValue
            lock.unlock()
        }
    }

    var videoType: IRVideoType {
        lock.lock()
        defer { lock.unlock() }
        return storedVideoType
    }

    @discardableResult
    func setVideoType(_ value: IRVideoType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedVideoType != value else { return false }
        storedVideoType = value
        return true
    }

    var displayMode: IRDisplayMode {
        lock.lock()
        defer { lock.unlock() }
        return storedDisplayMode
    }

    @discardableResult
    func setDisplayMode(_ value: IRDisplayMode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedDisplayMode != value else { return false }
        storedDisplayMode = value
        return true
    }

    var autoplay: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAutoplay
        }
        set {
            lock.lock()
            storedAutoplay = newValue
            lock.unlock()
        }
    }

    var isLiveStream: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedIsLiveStream
        }
        set {
            lock.lock()
            storedIsLiveStream = newValue
            lock.unlock()
        }
    }

    var playableBufferInterval: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedPlayableBufferInterval
        }
        set {
            lock.lock()
            storedPlayableBufferInterval =
                IRPlayerConfiguration.normalizedBufferInterval(newValue)
            lock.unlock()
        }
    }

    var volume: CGFloat {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedVolume
        }
        set {
            lock.lock()
            storedVolume = IRPlayerConfiguration.normalizedVolume(newValue)
            lock.unlock()
        }
    }

    var viewAnimationHidden: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedViewAnimationHidden
        }
        set {
            lock.lock()
            storedViewAnimationHidden = newValue
            lock.unlock()
        }
    }

    var error: IRError? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedError
        }
        set {
            lock.lock()
            storedError = newValue
            lock.unlock()
        }
    }

    var tapAction: TapAction? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedTapAction
        }
        set {
            lock.lock()
            storedTapAction = newValue
            lock.unlock()
        }
    }
}

final class IRPlayerMediaSession: @unchecked Sendable {
    struct Snapshot {
        let source: IRMediaSource?
        let contentURL: NSURL?
        let contentHeaders: [String: String]?
        let videoInput: IRFFVideoInput?
    }

    struct Replacement {
        let previousVideoInput: IRFFVideoInput?
        let currentVideoInput: IRFFVideoInput?
    }

    private let mutationLock = NSRecursiveLock()
    private let lock = NSLock()
    private var source: IRMediaSource?
    private var contentURL: NSURL?
    private var contentHeaders: [String: String]?
    private var videoInput: IRFFVideoInput?

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            source: source,
            contentURL: contentURL,
            contentHeaders: contentHeaders,
            videoInput: videoInput
        )
    }

    @discardableResult
    func replace(with source: IRMediaSource) -> Replacement {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        lock.lock()
        let previous = videoInput
        self.source = source
        contentURL = source.url as NSURL?
        contentHeaders = source.headers.isEmpty ? nil : source.headers
        videoInput = source.videoInput
        let current = videoInput
        lock.unlock()
        if previous !== current {
            previous?.videoOutput = nil
        }
        return Replacement(
            previousVideoInput: previous,
            currentVideoInput: current
        )
    }

    @discardableResult
    func clear() -> IRFFVideoInput? {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        lock.lock()
        let previous = videoInput
        source = nil
        contentURL = nil
        contentHeaders = nil
        videoInput = nil
        lock.unlock()
        previous?.videoOutput = nil
        return previous
    }

    func setLegacyHeaders(_ headers: [String: String]?) {
        lock.lock()
        contentHeaders = headers?.isEmpty == false ? headers : nil
        lock.unlock()
    }

    func bindCurrentVideoInput(to output: IRFFDecoderVideoOutput?) {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        lock.lock()
        let input = videoInput
        lock.unlock()
        input?.videoOutput = output
    }
}
