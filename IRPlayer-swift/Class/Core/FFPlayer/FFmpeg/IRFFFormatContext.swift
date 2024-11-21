//
//  IRFFFormatContext.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/12.
//

import Foundation
import CoreGraphics

public protocol IRFFFormatContextDelegate: AnyObject {
    func formatContextNeedInterrupt(_ formatContext: IRFFFormatContext) -> Bool
}

public class IRFFFormatContext {
    weak var delegate: IRFFFormatContextDelegate?

    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private(set) var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private(set) var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?

    private var contentURL: URL
    private(set) var error: NSError?
    private(set) var metadata: [AnyHashable: Any] = [:]
    var bitrate: TimeInterval {
        guard let formatContext = formatContext else {
            return 0
        }
        return Double(formatContext.pointee.bit_rate) / 1000.0
    }
    var duration: TimeInterval {
        guard let formatContext = formatContext else {
            return 0
        }
        guard formatContext.pointee.duration != IR_AV_NOPTS_VALUE else {
            return TimeInterval(MAXFLOAT)
        }
        return TimeInterval(formatContext.pointee.duration / Int64(AV_TIME_BASE))
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

    static public func formatContext(with contentURL: URL, delegate: IRFFFormatContextDelegate?) -> IRFFFormatContext {
        return IRFFFormatContext(contentURL: contentURL, delegate: delegate)
    }

    private init(contentURL: URL, delegate: IRFFFormatContextDelegate?) {
        self.contentURL = contentURL
        self.delegate = delegate
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
        formatContext?.pointee.interrupt_callback.opaque = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

        result = avformat_open_input(&formatContext, contentURL.absoluteString, nil, nil)
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
            let stream = formatContext?.pointee.streams[i]
            switch stream?.pointee.codecpar.pointee.codec_type {
            case AVMEDIA_TYPE_VIDEO:
                let track = IRFFTrack(index: i, type: .video)
                videoTracks.append(track)
            case AVMEDIA_TYPE_AUDIO:
                let track = IRFFTrack(index: i, type: .audio)
                audioTracks.append(track)
            default:
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
                if ((formatContext?.pointee.streams[Int(index)]?.pointee.disposition)! & AV_DISPOSITION_ATTACHED_PIC) == 0 {
                    var codecContext: UnsafeMutablePointer<AVCodecContext>?
                    error = openStream(with: Int(index), codecContext: &codecContext, domain: "video")
                    if error == nil {
                        self.videoTrack = track
                        self.videoEnable = true
                        self.videoTimebase = IRFFStreamGetTimebase((formatContext?.pointee.streams[Int(index)])!, defaultTimebase: 0.00004)
                        self.videoFPS = IRFFStreamGetFPS((formatContext?.pointee.streams[Int(index)])!, timebase: self.videoTimebase)
                        self.videoPresentationSize = CGSize(width: CGFloat(codecContext?.pointee.width ?? 0), height: CGFloat(codecContext?.pointee.height ?? 0))
                        self.videoAspect = CGFloat(codecContext?.pointee.width ?? 0) / CGFloat(codecContext?.pointee.height ?? 0)
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
                    self.audioTimebase = IRFFStreamGetTimebase((formatContext?.pointee.streams[Int(index)])!, defaultTimebase: 0.000025)
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

        let stream = formatContext?.pointee.streams[trackIndex]
        codecContext = avcodec_alloc_context3(nil)
        if codecContext == nil {
            error = NSError(domain: "\(domain) codec context create error", code: Int(IRFFDecoderErrorCode.codecContextCreate.rawValue), userInfo: nil)
            return error
        }

        result = avcodec_parameters_to_context(codecContext, stream?.pointee.codecpar)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.codecContextSetParam.rawValue)
        if error != nil {
            avcodec_free_context(&codecContext)
            return error
        }
        av_codec_set_pkt_timebase(codecContext, (stream?.pointee.time_base)!)

        let codec = avcodec_find_decoder((codecContext?.pointee.codec_id)!)
        if codec == nil {
            avcodec_free_context(&codecContext)
            error = NSError(domain: "\(domain) codec not found decoder", code: Int(IRFFDecoderErrorCode.codecFindDecoder.rawValue), userInfo: nil)
            return error
        }
        codecContext?.pointee.codec_id = (codec?.pointee.id)!

        result = avcodec_open2(codecContext, codec, nil)
        error = IRFFCheckErrorCode(result, errorCode: IRFFDecoderErrorCode.codecOpen2.rawValue)
        if error != nil {
            avcodec_free_context(&codecContext)
            return error
        }

        return error
    }

    func seekFile(withFFTimebase time: TimeInterval) {
        let ts = Int64(time * Double(AV_TIME_BASE))
        av_seek_frame(formatContext, -1, ts, AVSEEK_FLAG_BACKWARD)
    }

    func readFrame(_ packet: UnsafeMutablePointer<AVPacket>) -> Int32 {
        return av_read_frame(formatContext, packet)
    }

    func containAudioTrack(_ audioTrackIndex: Int) -> Bool {
        return audioTracks.contains { $0.index == audioTrackIndex }
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
            audioTimebase = IRFFStreamGetTimebase((formatContext?.pointee.streams[audioTrackIndex])!, defaultTimebase: 0.000025)
            audioCodecContext = codecContext
        } else {
            print("select audio track error: \(String(describing: error))")
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
        print("IRFFFormatContext release")
    }
}

func ffmpeg_interrupt_callback(ctx: UnsafeMutableRawPointer?) -> Int32 {
    let obj = Unmanaged<IRFFFormatContext>.fromOpaque(ctx!).takeUnretainedValue()
    return obj.delegate?.formatContextNeedInterrupt(obj) == true ? 1 : 0
}

