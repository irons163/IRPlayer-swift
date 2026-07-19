import Foundation

public enum IRPlaybackBackendPreference: Int, Hashable, Sendable {
    case automatic
    case avFoundation
    case ffmpeg
}

public struct IRMediaSource {
    public var url: URL?
    public var headers: [String: String]
    public var videoType: IRVideoType
    public var videoInput: IRFFVideoInput?
    public var backendPreference: IRPlaybackBackendPreference

    public init(
        url: URL?,
        headers: [String: String] = [:],
        videoType: IRVideoType = .normal,
        videoInput: IRFFVideoInput? = nil,
        backendPreference: IRPlaybackBackendPreference = .automatic
    ) {
        self.url = url
        self.headers = headers
        self.videoType = videoType
        self.videoInput = videoInput
        self.backendPreference = backendPreference
    }

    static var empty: IRMediaSource {
        IRMediaSource(url: nil)
    }

    func decoderType(using decoder: IRPlayerDecoder) -> IRDecoderType {
        guard let url else { return .error }

        switch backendPreference {
        case .automatic:
            return decoder.decoderTypeForContentURL(contentURL: url as NSURL)
        case .avFoundation:
            return .avPlayer
        case .ffmpeg:
            return .ffmpeg
        }
    }
}

/// Preferred Swift name for the 2.x player facade.
public typealias IRPlayer = IRPlayerImp
