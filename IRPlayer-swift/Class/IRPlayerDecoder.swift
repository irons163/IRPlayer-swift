//
//  IRPlayerDecoder.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import Foundation

public enum IRDecoderType {
    case error
    case avPlayer
    case ffmpeg
}

enum IRVideoFormat {
    case error
    case unknown
    case mpeg4
    case flv
    case m3u8
    case rtmp
    case rtsp
}

@objcMembers
public class IRPlayerDecoder: NSObject {

    public var ffmpegHardwareDecoderEnable: Bool = true
    var unkonwnFormat: IRDecoderType = .ffmpeg
    public var mpeg4Format: IRDecoderType = .avPlayer
    var flvFormat: IRDecoderType = .ffmpeg
    var m3u8Format: IRDecoderType = .avPlayer
    var rtmpFormat: IRDecoderType = .ffmpeg
    var rtspFormat: IRDecoderType = .ffmpeg

    class func defaultDecoder() -> IRPlayerDecoder {
        let decoder = IRPlayerDecoder()
        decoder.unkonwnFormat = .ffmpeg
        decoder.mpeg4Format = .avPlayer
        decoder.flvFormat = .ffmpeg
        decoder.m3u8Format = .avPlayer
        decoder.rtmpFormat = .ffmpeg
        decoder.rtspFormat = .ffmpeg
        return decoder
    }

    class func AVPlayerDecoder() -> IRPlayerDecoder {
        let decoder = IRPlayerDecoder()
        decoder.unkonwnFormat = .avPlayer
        decoder.mpeg4Format = .avPlayer
        decoder.flvFormat = .avPlayer
        decoder.m3u8Format = .avPlayer
        decoder.rtmpFormat = .avPlayer
        decoder.rtspFormat = .avPlayer
        return decoder
    }

    public class func FFmpegDecoder() -> IRPlayerDecoder {
        let decoder = IRPlayerDecoder()
        decoder.unkonwnFormat = .ffmpeg
        decoder.mpeg4Format = .ffmpeg
        decoder.flvFormat = .ffmpeg
        decoder.m3u8Format = .ffmpeg
        decoder.rtmpFormat = .ffmpeg
        decoder.rtspFormat = .ffmpeg
        return decoder
    }

    func formatForContentURL(contentURL: NSURL?) -> IRVideoFormat {
        guard let contentURL = contentURL else { return .error }

        let path: String
        if contentURL.isFileURL {
            path = contentURL.path ?? ""
        } else {
            path = contentURL.absoluteString ?? ""
        }

        switch path {
        case _ where path.hasPrefix("rtmp:"):
            return .rtmp
        case _ where path.hasPrefix("rtsp:"):
            return .rtsp
        case _ where path.contains(".flv"):
            return .flv
        case _ where path.contains(".mp4"):
            return .mpeg4
        case _ where path.contains(".m3u8"):
            return .m3u8
        default:
            return .unknown
        }
    }

    func decoderTypeForContentURL(contentURL: NSURL?) -> IRDecoderType {
        let format = self.formatForContentURL(contentURL: contentURL)
        switch format {
        case .error:
            return .error
        case .unknown:
            return self.unkonwnFormat
        case .mpeg4:
            return self.mpeg4Format
        case .flv:
            return self.flvFormat
        case .m3u8:
            return self.m3u8Format
        case .rtmp:
            return self.rtmpFormat
        case .rtsp:
            return self.rtspFormat
        }
    }
}
