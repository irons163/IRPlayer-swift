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
        switch backendResolution(using: decoder) {
        case let .backend(kind):
            return kind.decoderType
        case .missingURL,
             .unsupportedSource,
             .unsupportedAVFoundation:
            return .error
        }
    }

    func backendResolution(
        using decoder: IRPlayerDecoder
    ) -> IRMediaSourceBackendResolution {
        guard let url else { return .missingURL }
        // AVFoundation cannot guarantee custom headers on every HLS
        // playlist and segment request through a supported public API.
        let requiresFFmpeg =
            !headers.isEmpty
            || videoInput != nil
            || !Self.avFoundationVideoTypes.contains(videoType)

        switch backendPreference {
        case .automatic:
            if requiresFFmpeg {
                return .backend(.ffmpeg)
            }
            guard let kind = decoder
                .decoderTypeForContentURL(contentURL: url as NSURL)
                .playbackBackendKind else {
                return .unsupportedSource
            }
            return .backend(kind)

        case .avFoundation:
            return requiresFFmpeg
                ? .unsupportedAVFoundation
                : .backend(.avFoundation)

        case .ffmpeg:
            return .backend(.ffmpeg)
        }
    }

    private static let avFoundationVideoTypes: Set<IRVideoType> = [
        .normal,
        .vr
    ]
}

enum IRMediaSourceBackendResolution: Equatable {
    case backend(IRPlaybackBackendKind)
    case missingURL
    case unsupportedSource
    case unsupportedAVFoundation
}

/// Preferred Swift name for the 2.x player facade.
public typealias IRPlayer = IRPlayerImp
