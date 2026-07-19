import CoreGraphics
import Foundation

public enum IRPlayerBackgroundPolicy: Int, Hashable, Sendable {
    case pauseAndResume
    case continuePlayback
}

public struct IRPlayerConfiguration {
    public var decoder: IRPlayerDecoder
    public var autoplay: Bool
    public var isLiveStream: Bool
    public var gravityMode: IRGravityMode
    public var displayMode: IRDisplayMode
    public var backgroundPolicy: IRPlayerBackgroundPolicy

    private var storedPlayableBufferInterval: TimeInterval
    private var storedVolume: CGFloat

    public var playableBufferInterval: TimeInterval {
        get { storedPlayableBufferInterval }
        set { storedPlayableBufferInterval = Self.normalizedBufferInterval(newValue) }
    }

    public var volume: CGFloat {
        get { storedVolume }
        set { storedVolume = Self.normalizedVolume(newValue) }
    }

    public init(
        decoder: IRPlayerDecoder = IRPlayerDecoder.defaultDecoder(),
        autoplay: Bool = false,
        isLiveStream: Bool = false,
        playableBufferInterval: TimeInterval = 2,
        volume: CGFloat = 1,
        gravityMode: IRGravityMode = .resizeAspect,
        displayMode: IRDisplayMode = .normal,
        backgroundPolicy: IRPlayerBackgroundPolicy = .pauseAndResume
    ) {
        self.decoder = decoder
        self.autoplay = autoplay
        self.isLiveStream = isLiveStream
        self.gravityMode = gravityMode
        self.displayMode = displayMode
        self.backgroundPolicy = backgroundPolicy
        self.storedPlayableBufferInterval = Self.normalizedBufferInterval(playableBufferInterval)
        self.storedVolume = Self.normalizedVolume(volume)
    }

    static func normalizedBufferInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 2 }
        return max(0, value)
    }

    static func normalizedVolume(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }
}

extension IRPlayerBackgroundPolicy {
    var lifecycleMode: IRPlayerBackgroundMode {
        switch self {
        case .pauseAndResume:
            return .autoPlayAndPause
        case .continuePlayback:
            return .continuing
        }
    }
}

extension IRPlayerBackgroundMode {
    var publicPolicy: IRPlayerBackgroundPolicy {
        switch self {
        case .autoPlayAndPause:
            return .pauseAndResume
        case .nothing, .continuing:
            return .continuePlayback
        }
    }
}
