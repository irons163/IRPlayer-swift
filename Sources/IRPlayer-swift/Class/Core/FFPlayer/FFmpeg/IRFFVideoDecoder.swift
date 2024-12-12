//
//  IRFFVideoDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/13.
//

import Foundation
import AVFoundation
import IRFFMpeg
import IRPlayerObjc

protocol IRFFVideoDecoderDelegate: AnyObject {
    func videoDecoder(_ videoDecoder: IRFFVideoDecoder, didError error: Error)
    func videoDecoderNeedUpdateBufferedDuration(_ videoDecoder: IRFFVideoDecoder)
    func videoDecoderNeedCheckBufferingStatus(_ videoDecoder: IRFFVideoDecoder)
}

class IRFFVideoDecoder {
    private var codecContext: UnsafeMutablePointer<AVCodecContext>
    private var tempFrame: UnsafeMutablePointer<AVFrame>?
    private var packetQueue: IRFFPacketQueue
    private var frameQueue: IRFFFrameQueue
    private var framePool: IRFFFramePool?
    private lazy var videoToolBox: IRFFVideoToolBox = {
        return IRFFVideoToolBox(codecContext: codecContext)
    }()
    private var canceled = false
    private(set) var error: NSError?
    private(set) var decoding = false

    weak var delegate: IRFFVideoDecoderDelegate?
    var videoToolBoxEnable = true
    var maxDecodeDuration: TimeInterval = 2.0
    var timebase: TimeInterval
    var fps: TimeInterval
    var paused = false
    var endOfFile = false

    static var flushPacket: AVPacket = {
        var packet = AVPacket()
        av_init_packet(&packet)
//        packet.data = UnsafeMutablePointer(mutating: &packet)
//        packet.data = UnsafeMutablePointer(mutating: &packet as UnsafePointer<AVPacket>)
//        var tempPacket = packet
        packet.data = withUnsafeMutablePointer(to: &packet) {
            return UnsafeMutableRawPointer($0).assumingMemoryBound(to: UInt8.self)
        }
        packet.duration = 0
        return packet
    }()

    init(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, fps: TimeInterval, delegate: IRFFVideoDecoderDelegate?) {
        self.codecContext = codecContext
        self.timebase = timebase
        self.fps = fps
        self.delegate = delegate
        self.tempFrame = av_frame_alloc()
        self.packetQueue = IRFFPacketQueue(timebase: timebase)
        self.frameQueue = IRFFFrameQueue()
    }

    func packetSize() -> Int {
        return Int(packetQueue.size)
    }

    func empty() -> Bool {
        return packetEmpty() && frameEmpty()
    }

    func packetEmpty() -> Bool {
        return packetQueue.count <= 0
    }

    func frameEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    func duration() -> TimeInterval {
        return packetDuration() + frameDuration()
    }

    func packetDuration() -> TimeInterval {
        return packetQueue.duration
    }

    func frameDuration() -> TimeInterval {
        return frameQueue.duration
    }

    func getFrameSync() -> IRFFVideoFrame? {
        return frameQueue.getFrameSync() as! IRFFVideoFrame
    }

    func getFrameAsync() -> IRFFVideoFrame? {
        return frameQueue.getFrameAsync() as! IRFFVideoFrame
    }

    func putPacket(_ packet: AVPacket) {
        var duration: TimeInterval = 0
        if packet.duration <= 0 && packet.size > 0 && packet.data != IRFFVideoDecoder.flushPacket.data {
            duration = 1.0 / fps
        }
        packetQueue.putPacket(packet, duration: duration)
    }

    func flush() {
        packetQueue.flush()
        frameQueue.flush()
        framePool?.flush()
        putPacket(IRFFVideoDecoder.flushPacket)
    }

    func destroy() {
        canceled = true
        frameQueue.destroy()
        packetQueue.destroy()
        framePool?.flush()
    }

    func decodeFrameThread() {
        decoding = true
        var finished = false
        while !finished {
            if canceled || error != nil {
                print("decode video thread quit")
                break
            }
            if paused {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            if endOfFile && packetEmpty() {
                print("decode video finished")
                break
            }
            if frameDuration() >= maxDecodeDuration {
                let interval = paused ? max_video_frame_sleep_full_and_pause_time_interval : max_video_frame_sleep_full_time_interval
                print("decode video thread sleep : \(interval)")
                Thread.sleep(forTimeInterval: interval)
                continue
            }

            var packet = packetQueue.getPacket()
            if endOfFile {
                delegate?.videoDecoderNeedUpdateBufferedDuration(self)
            }
            if packet.data == IRFFVideoDecoder.flushPacket.data {
                print("video codec flush")
                avcodec_flush_buffers(codecContext)
                videoToolBox.flush()
                continue
            }
            if packet.stream_index < 0 || packet.data == nil { continue }

            var videoFrame: IRFFVideoFrame?
            if videoToolBoxEnable && codecContext.pointee.codec_id == AV_CODEC_ID_H264 {
                if videoToolBox.trySetupVTSession() {
                    if videoToolBox.sendPacket(packet) {
                        videoFrame = videoFrameFromVideoToolBox(packet: packet)
                    }
                }
            } else {
                var result = avcodec_send_packet(codecContext, &packet)
                if result < 0 && result != AVERROR(EAGAIN) && result != IR_AVERROR_EOF {
                    error = IRFFCheckError(result)
                    delegateErrorCallback()
                    return
                }
                while result >= 0 {
                    result = avcodec_receive_frame(codecContext, tempFrame)
                    if result < 0 {
                        if result == AVERROR(EAGAIN) || result == IR_AVERROR_EOF {
                            break
                        } else {
                            error = IRFFCheckError(result)
                            delegateErrorCallback()
                            return
                        }
                    }
                    videoFrame = videoFrameFromTempFrame()
                }
            }
            if let videoFrame = videoFrame {
                frameQueue.putSortFrame(videoFrame)
            }
            av_packet_unref(&packet)
        }
        decoding = false
        delegate?.videoDecoderNeedCheckBufferingStatus(self)
    }

    private func videoFrameFromTempFrame() -> IRFFAVYUVVideoFrame? {
        guard let frame = tempFrame, frame.pointee.data.0 != nil, frame.pointee.data.1 != nil, frame.pointee.data.2 != nil else {
            return nil
        }

        let videoFrame = framePool?.getUnuseFrame() as? IRFFAVYUVVideoFrame ?? IRFFAVYUVVideoFrame()
        videoFrame.setFrameData(frame, width: Int(codecContext.pointee.width), height: Int(codecContext.pointee.height))
//        videoFrame.position = Double(av_frame_get_best_effort_timestamp(frame)) * timebase
        videoFrame.position = Double(frame.pointee.best_effort_timestamp) * timebase

//        let frameDuration = av_frame_get_pkt_duration(frame)
        let frameDuration = frame.pointee.duration
        if frameDuration != 0 {
            videoFrame.duration = TimeInterval(frameDuration) * timebase + TimeInterval(frame.pointee.repeat_pict) * timebase * 0.5
        } else {
            videoFrame.duration = 1.0 / fps
        }
        return videoFrame
    }

    private func videoFrameFromVideoToolBox(packet: AVPacket) -> IRFFVideoFrame? {
        guard let imageBuffer = videoToolBox.imageBuffer() else {
            return nil
        }

        let videoFrame = IRFFCVYUVVideoFrame(pixelBuffer: imageBuffer)
        if packet.pts != IR_AV_NOPTS_VALUE {
            videoFrame.position = TimeInterval(packet.pts) * timebase
        } else {
            videoFrame.position = TimeInterval(packet.dts)
        }

        let frameDuration = packet.duration
        if frameDuration != 0 {
            videoFrame.duration = TimeInterval(frameDuration) * timebase
        } else {
            videoFrame.duration = 1.0 / fps
        }
        return videoFrame
    }

    private func delegateErrorCallback() {
        if let error = error {
            delegate?.videoDecoder(self, didError: error)
        }
    }

    deinit {
        if let frame = tempFrame {
            av_free(frame)
        }
        print("IRFFVideoDecoder release")
    }
}

private var max_video_frame_sleep_full_time_interval: TimeInterval = 0.1
private var max_video_frame_sleep_full_and_pause_time_interval: TimeInterval = 0.5
