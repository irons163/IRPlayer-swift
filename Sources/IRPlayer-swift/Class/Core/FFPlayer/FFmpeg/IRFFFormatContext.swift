//
//  IRFFFormatContext.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/12.
//

import Foundation
import CoreGraphics
import IRFFMpeg
import IRPlayerObjc

public protocol IRFFFormatContextDelegate: AnyObject {
    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool
}

public class IRFFFormatContext {
    weak var delegate: IRFFFormatContextDelegate?

    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private(set) var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private(set) var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    private var contentURL: URL
    private var videoFormat: IRVideoFormat
    private(set) var error: NSError?
    private(set) var metadata: [AnyHashable: Any] = [:]
    var bitrate: TimeInterval {
        guard let formatContext = formatContext else {
            return 0
        }
        return Self.bitrateKbps(from: formatContext.pointee.bit_rate)
    }
    var duration: TimeInterval {
        guard let formatContext = formatContext else {
            return 0
        }
        return Self.durationSeconds(from: formatContext.pointee.duration)
    }
    private(set) var videoEnable: Bool = false
    private(set) var audioEnable: Bool = false
    private(set) var videoTrack: IRFFTrack?
    private(set) var audioTrack: IRFFTrack?
    private(set) var videoTracks: [IRFFTrack] = []
    private(set) var audioTracks: [IRFFTrack] = []
    private(set) var videoTimebase: TimeInterval = 0
    private(set) var videoFPS: TimeInterval = 0
    private(set) var videoPresentationSize: CGSize = .zero
    private(set) var videoAspect: CGFloat = 0
    private(set) var audioTimebase: TimeInterval = 0

    init(contentURL: URL, videoFormat: IRVideoFormat) {
        self.contentURL = contentURL
        self.videoFormat = videoFormat
    }

    static func stream(at index: Int, in formatContext: UnsafeMutablePointer<AVFormatContext>?) -> UnsafeMutablePointer<AVStream>? {
        guard let formatContext,
              index >= 0,
              index < Int(formatContext.pointee.nb_streams),
              let streams = formatContext.pointee.streams else {
            return nil
        }

        return streams[index]
    }

    static func decoder(for codecContext: UnsafeMutablePointer<AVCodecContext>?) -> UnsafePointer<AVCodec>? {
        guard let codecContext else { return nil }
        return avcodec_find_decoder(codecContext.pointee.codec_id)
    }

    static func durationSeconds(from duration: Int64) -> TimeInterval {
        guard duration != IR_AV_NOPTS_VALUE else {
            return TimeInterval(MAXFLOAT)
        }
        guard duration >= 0 else { return 0 }
        let seconds = TimeInterval(duration) / TimeInterval(AV_TIME_BASE)
        return seconds.isFinite ? seconds : 0
    }

    static func bitrateKbps(from bitRate: Int64) -> TimeInterval {
        guard bitRate >= 0 else { return 0 }
        let bitrate = TimeInterval(bitRate) / 1000.0
        return bitrate.isFinite ? bitrate : 0
    }

    static func presentationSize(width: Int32, height: Int32) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    static func interruptOpaquePointer(for context: IRFFFormatContext) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
    }

    func setupSync() {
        self.error = openStream()
        if error != nil { return }

        openTracks()
        let videoError = openVideoTrack()
        let audioError = openAudioTrack()

        guard let videoError = videoError, let audioError = audioError else {
            return
        }
        
        if videoError.code == IRFFDecoderErrorCode.streamNotFound.rawValue && audioError.code != IRFFDecoderErrorCode.streamNotFound.rawValue {
            self.error = audioError
        } else {
            self.error = videoError
        }
        return
    }

    private func openStream() -> NSError? {
        var result: Int32 = 0
        var error: NSError?

        self.formatContext = avformat_alloc_context()
        if formatContext == nil {
            result = -1
            error = NSError(domain: "IRFFDecoderErrorCodeFormatCreate error", code: Int(IRFFDecoderErrorCode.formatCreate.rawValue), userInfo: nil)
            return error
        }

        formatContext?.pointee.interrupt_callback.callback = ffmpeg_interrupt_callback
        formatContext?.pointee.interrupt_callback.opaque = Self.interruptOpaquePointer(for: self)

        var opts = AVDictionary(rawPointer: nil)
        if videoFormat == .rtsp {
            let ret = av_dict_set(&opts.rawPointer, "rtsp_transport", "tcp", 0)
            if ret < 0 {
                IRPlayerImp.Logger.libraryLogger.debug("Failed to set dictionary option: \(ret)")
            }
        }
        result = avformat_open_input(&formatContext, contentURL.absoluteString, nil, &opts.rawPointer)
        av_dict_free(&opts.rawPointer)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.formatOpenInput.rawValue)
        if error != nil || formatContext == nil {
            if formatContext != nil {
                avformat_free_context(formatContext)
            }
            return error
        }

        result = avformat_find_stream_info(formatContext, nil)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.formatFindStreamInfo.rawValue)
        if error != nil || formatContext == nil {
            if formatContext != nil {
                avformat_close_input(&formatContext)
            }
            return error
        }
//        self.metadata = IRFFFoundationBrigeOfAVDictionary((formatContext?.pointee.metadata)! as? [Character: Any])
//        self.metadata = IRFFFoundationBrigeOfAVDictionary(formatContext?.pointee.metadata)
        if let avDict = formatContext?.pointee.metadata {
            self.metadata = IRFFFoundationBrigeOfAVDictionary(avDict) ?? [:]
        } else {
            self.metadata = [:]
        }

        return error
    }

    private func openTracks() {
        var videoTracks: [IRFFTrack] = []
        var audioTracks: [IRFFTrack] = []

        for i in 0..<Int((formatContext?.pointee.nb_streams ?? 0)) {
            guard let stream = Self.stream(at: i, in: formatContext),
                  let codecParameters = stream.pointee.codecpar else { continue }

            let metadata = IRFFFoundationBrigeOfAVDictionary(stream.pointee.metadata).map(IRFFMetadata.init(dictionary:))
            guard let track = Self.track(index: i, codecType: codecParameters.pointee.codec_type, metadata: metadata) else {
                continue
            }

            switch track.type {
            case .video:
                videoTracks.append(track)
            case .audio:
                audioTracks.append(track)
            case .subtitle:
                break
            }
        }

        if !videoTracks.isEmpty {
            self.videoTracks = videoTracks
        }
        if !audioTracks.isEmpty {
            self.audioTracks = audioTracks
        }
    }

    private func openVideoTrack() -> NSError? {
        var error: NSError?

        if !videoTracks.isEmpty {
            for track in videoTracks {
                let index = track.index
                guard let stream = Self.stream(at: Int(index), in: formatContext) else { continue }

                if (stream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC) == 0 {
                    var codecContext: UnsafeMutablePointer<AVCodecContext>?
                    error = openStream(with: Int(index), codecContext: &codecContext, domain: "video")
                    if error == nil {
                        self.videoTrack = track
                        self.videoEnable = true
                        self.videoTimebase = IRFFStreamGetTimebase(stream, defaultTimebase: 0.00004)
                        self.videoFPS = IRFFStreamGetFPS(stream, timebase: self.videoTimebase)
                        self.videoPresentationSize = Self.presentationSize(width: codecContext?.pointee.width ?? 0, height: codecContext?.pointee.height ?? 0)
                        self.videoAspect = Self.videoAspect(width: codecContext?.pointee.width ?? 0, height: codecContext?.pointee.height ?? 0)
                        self.videoCodecContext = codecContext
                        break
                    }
                }
            }
        } else {
            error = NSError(domain: "video stream not found", code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue), userInfo: nil)
        }

        return error
    }

    private func openAudioTrack() -> NSError? {
        var error: NSError?

        if !audioTracks.isEmpty {
            for track in audioTracks {
                let index = track.index
                var codecContext: UnsafeMutablePointer<AVCodecContext>?
                error = openStream(with: Int(index), codecContext: &codecContext, domain: "audio")
                if error == nil {
                    self.audioTrack = track
                    self.audioEnable = true
                    if let stream = Self.stream(at: Int(index), in: formatContext) {
                        self.audioTimebase = IRFFStreamGetTimebase(stream, defaultTimebase: 0.000025)
                    }
                    self.audioCodecContext = codecContext
                    break
                }
            }
        } else {
            error = NSError(domain: "audio stream not found", code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue), userInfo: nil)
        }

        return error
    }

    private func openStream(with trackIndex: Int, codecContext: inout UnsafeMutablePointer<AVCodecContext>?, domain: String) -> NSError? {
        var result: Int32 = 0
        var error: NSError?

        guard let stream = Self.stream(at: trackIndex, in: formatContext),
              let codecParameters = stream.pointee.codecpar else {
            error = NSError(domain: "\(domain) stream not found", code: Int(IRFFDecoderErrorCode.streamNotFound.rawValue), userInfo: nil)
            return error
        }

        codecContext = avcodec_alloc_context3(nil)
        if codecContext == nil {
            error = NSError(domain: "\(domain) codec context create error", code: Int(IRFFDecoderErrorCode.codecContextCreate.rawValue), userInfo: nil)
            return error
        }
        guard let openedCodecContext = codecContext else {
            error = NSError(domain: "\(domain) codec context create error", code: Int(IRFFDecoderErrorCode.codecContextCreate.rawValue), userInfo: nil)
            return error
        }

        result = avcodec_parameters_to_context(codecContext, codecParameters)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.codecContextSetParam.rawValue)
        if error != nil {
            avcodec_free_context(&codecContext)
            return error
        }
//        av_codec_set_pkt_timebase(codecContext, (stream?.pointee.time_base)!)
        openedCodecContext.pointee.pkt_timebase = stream.pointee.time_base

        guard let codec = Self.decoder(for: openedCodecContext) else {
            avcodec_free_context(&codecContext)
            error = NSError(domain: "\(domain) codec not found decoder", code: Int(IRFFDecoderErrorCode.codecFindDecoder.rawValue), userInfo: nil)
            return error
        }
        openedCodecContext.pointee.codec_id = codec.pointee.id

        result = avcodec_open2(codecContext, codec, nil)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.codecOpen2.rawValue)
        if error != nil {
            avcodec_free_context(&codecContext)
            return error
        }

        return error
    }

    static func seekTimestamp(for time: TimeInterval) -> Int64? {
        guard time.isFinite, time >= 0 else { return nil }
        let timestamp = time * Double(AV_TIME_BASE)
        guard timestamp.isFinite,
              timestamp >= 0,
              timestamp <= Double(Int64.max) else {
            return nil
        }
        return Int64(timestamp)
    }

    func seekFile(withFFTimebase time: TimeInterval) {
        guard let ts = Self.seekTimestamp(for: time) else { return }
        av_seek_frame(formatContext, -1, ts, AVSEEK_FLAG_BACKWARD)
    }

    func readFrame(_ packet: UnsafeMutablePointer<AVPacket>) -> Int32 {
        return av_read_frame(formatContext, packet)
    }

    func containAudioTrack(_ audioTrackIndex: Int) -> Bool {
        return audioTracks.contains { $0.index == audioTrackIndex }
    }

    static func track(index: Int, codecType: AVMediaType, metadata: IRFFMetadata?) -> IRFFTrack? {
        switch codecType {
        case AVMEDIA_TYPE_VIDEO:
            return IRFFTrack(index: index, type: .video, metadata: metadata)
        case AVMEDIA_TYPE_AUDIO:
            return IRFFTrack(index: index, type: .audio, metadata: metadata)
        default:
            return nil
        }
    }

    static func videoAspect(width: Int32, height: Int32) -> CGFloat {
        guard width > 0, height > 0 else { return 0 }
        let aspect = CGFloat(width) / CGFloat(height)
        return aspect.isFinite ? aspect : 0
    }

    func selectAudioTrackIndex(_ audioTrackIndex: Int) -> NSError? {
        guard audioTrackIndex != (audioTrack?.index ?? -1),
              containAudioTrack(audioTrackIndex) else { return nil }

        var codecContext: UnsafeMutablePointer<AVCodecContext>?
        let error = openStream(with: audioTrackIndex, codecContext: &codecContext, domain: "audio select")
        if error == nil {
            if audioCodecContext != nil {
                avcodec_close(audioCodecContext)
                audioCodecContext = nil
            }
            audioTrack = audioTracks.first { $0.index == audioTrackIndex }
            audioEnable = true
            if let stream = Self.stream(at: audioTrackIndex, in: formatContext) {
                audioTimebase = IRFFStreamGetTimebase(stream, defaultTimebase: 0.000025)
            }
            audioCodecContext = codecContext
        } else {
            IRPlayerImp.Logger.libraryLogger.debug("select audio track error: \(String(describing: error))")
        }
        return error
    }

    var contentURLString: String {
        if contentURL.isFileURL {
            return contentURL.path
        } else {
            return contentURL.absoluteString
        }
    }

    func destroyAudioTrack() {
        audioEnable = false
        audioTrack = nil
        audioTracks = []

        if audioCodecContext != nil {
            avcodec_close(audioCodecContext)
            audioCodecContext = nil
        }
    }

    func destroyVideoTrack() {
        videoEnable = false
        videoTrack = nil
        videoTracks = []

        if videoCodecContext != nil {
            avcodec_close(videoCodecContext)
            videoCodecContext = nil
        }
    }

    func destroy() {
        destroyVideoTrack()
        destroyAudioTrack()
        if formatContext != nil {
            avformat_close_input(&formatContext)
            formatContext = nil
        }
    }

    deinit {
        destroy()
        IRPlayerImp.Logger.libraryLogger.debug("IRFFFormatContext release")
    }
}

func ffmpeg_interrupt_callback(ctx: UnsafeMutableRawPointer?) -> Int32 {
    guard let ctx else { return 0 }
    let obj = Unmanaged<IRFFFormatContext>.fromOpaque(ctx).takeUnretainedValue()
    return obj.delegate?.formatContextNeedInterrupt(obj) == true ? 1 : 0
}
