//
//  IRFFAudioDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/18.
//

import Foundation
import Accelerate

protocol IRFFAudioDecoderDelegate: AnyObject {
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, samplingRate: inout Float64)
    func audioDecoder(_ audioDecoder: IRFFAudioDecoder, channelCount: inout UInt32)
}

class IRFFAudioDecoder {

    weak var delegate: IRFFAudioDecoderDelegate?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var tempFrame: UnsafeMutablePointer<AVFrame>?
    private var timebase: TimeInterval
    private var samplingRate: Float64 = 0
    private var channelCount: UInt32 = 0
    private var audioSwrContext: OpaquePointer?
    private var audioSwrBuffer: UnsafeMutableRawPointer?
    private var audioSwrBufferSize: Int = 0

    private var frameQueue: IRFFFrameQueue
    private var framePool: IRFFFramePool

    static func decoder(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, delegate: IRFFAudioDecoderDelegate) -> IRFFAudioDecoder {
        return IRFFAudioDecoder(codecContext: codecContext, timebase: timebase, delegate: delegate)
    }

    private init(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, delegate: IRFFAudioDecoderDelegate) {
        self.codecContext = codecContext
        self.tempFrame = av_frame_alloc()
        self.timebase = timebase
        self.delegate = delegate
        self.frameQueue = IRFFFrameQueue()
        self.framePool = IRFFFramePool.audioPool()
        setup()
    }

    private func setup() {
        setupSwsContext()
    }

    private func setupSwsContext() {
        reloadAudioOutputInfo()

        audioSwrContext = swr_alloc_set_opts(nil, av_get_default_channel_layout(Int32(channelCount)), AV_SAMPLE_FMT_S16, Int32(samplingRate), av_get_default_channel_layout(codecContext?.pointee.channels ?? 0), codecContext?.pointee.sample_fmt ?? AV_SAMPLE_FMT_NONE, codecContext?.pointee.sample_rate ?? 0, 0, nil)

        let result = swr_init(audioSwrContext)
        let error: Error? = IRFFCheckError(result)
        if error != nil || audioSwrContext == nil {
            if audioSwrContext != nil {
                swr_free(&audioSwrContext)
            }
        }
    }

    func size() -> Int {
        return Int(frameQueue.size)
    }

    func isEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    func duration() -> TimeInterval {
        return frameQueue.duration
    }

    func flush() {
        frameQueue.flush()
        framePool.flush()
        if let codecContext = codecContext {
            avcodec_flush_buffers(codecContext)
        }
    }

    func destroy() {
        frameQueue.destroy()
        framePool.flush()
    }

    func getFrameSync() -> IRFFAudioFrame? {
        return frameQueue.getFrameSync() as? IRFFAudioFrame
    }

    func putPacket(_ packet: AVPacket) -> Int {
        var packet = packet
        if packet.data == nil { return 0 }

        var result = avcodec_send_packet(codecContext, &packet)
        if result < 0 && result != AVERROR(EAGAIN) && result != IR_AVERROR_EOF {
            return -1
        }

        while result >= 0 {
            result = avcodec_receive_frame(codecContext, tempFrame)
            if result < 0 {
                if result != AVERROR(EAGAIN) && result != IR_AVERROR_EOF {
                    return -1
                }
                break
            }
            autoreleasepool {
                if let frame = decode() {
                    frameQueue.putFrame(frame)
                }
            }
        }
        av_packet_unref(&packet)
        return 0
    }

    private func decode() -> IRFFAudioFrame? {
        guard let tempFrame = tempFrame, tempFrame.pointee.data.0 != nil else { return nil }

        reloadAudioOutputInfo()

        var numberOfFrames: Int
        var audioDataBuffer: UnsafeMutableRawPointer

        if let audioSwrContext = audioSwrContext {
            let ratio = max(1, Int(samplingRate / Float64(codecContext?.pointee.sample_rate ?? 1))) * max(1, Int(channelCount / UInt32(codecContext?.pointee.channels ?? 1))) * 2
            let bufferSize = av_samples_get_buffer_size(nil, Int32(channelCount), tempFrame.pointee.nb_samples * Int32(ratio), AV_SAMPLE_FMT_S16, 1)

            if audioSwrBuffer == nil || audioSwrBufferSize < bufferSize {
                audioSwrBufferSize = Int(bufferSize)
                audioSwrBuffer = realloc(audioSwrBuffer, audioSwrBufferSize)
            }

//            var outputBuffer = [audioSwrBuffer, nil].map { UnsafeMutablePointer<UInt8>($0) }
            var outputBuffer: [UnsafeMutablePointer<UInt8>?] = [audioSwrBuffer?.assumingMemoryBound(to: UInt8.self), nil]
//            var data: [UnsafeMutablePointer<UInt8>?] = [tempFrame.pointee.data, nil]
//            var a: UnsafeMutablePointer<UnsafePointer<UInt8>> = tempFrame.pointee.data
            // Create an array to hold the pointers
//            var inputBuffer = [UnsafePointer<UInt8>?](repeating: nil, count: Int(tempFrame.pointee.nb_samples))
//            for i in 0..<Int(codecContext!.pointee.channels) {
//                inputBuffer[i] = tempFrame.pointee.data[i]
//            }
//
//            // Convert the array to UnsafeMutablePointer<UnsafePointer<UInt8>?>
//            let inputPointer = UnsafeMutablePointer(mutating: inputBuffer)
//            let inputPointer: UnsafeMutablePointer<UnsafePointer<UInt8>?> = tempFrame.pointee.data.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: Int(codecContext!.pointee.channels)) {
//                        UnsafeMutablePointer<UnsafePointer<UInt8>?>(mutating: $0)
//                    }
            let inputPointer: UnsafeMutablePointer<UnsafePointer<UInt8>?> = withUnsafeMutablePointer(to: &tempFrame.pointee.data) {
                $0.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: Int(codecContext!.pointee.channels)) {
                    $0
                }
            }

            numberOfFrames = Int(swr_convert(audioSwrContext, &outputBuffer, tempFrame.pointee.nb_samples * Int32(ratio), inputPointer, tempFrame.pointee.nb_samples))
            let error: Error? = IRFFCheckError(Int32(numberOfFrames))
            if error != nil {
                IRFFErrorLog("audio codec error : \(String(describing: error))")
                return nil
            }
            audioDataBuffer = audioSwrBuffer!
        } else {
            if codecContext?.pointee.sample_fmt != AV_SAMPLE_FMT_S16 {
                IRFFErrorLog("audio format error")
                return nil
            }
            audioDataBuffer = UnsafeMutableRawPointer(tempFrame.pointee.data.0!)
            numberOfFrames = Int(tempFrame.pointee.nb_samples)
        }

        guard let audioFrame = framePool.getUnuseFrame() as? IRFFAudioFrame else {
            return nil
        }
        
        audioFrame.position = Double(av_frame_get_best_effort_timestamp(tempFrame)) * timebase
        audioFrame.duration = Double(av_frame_get_pkt_duration(tempFrame)) * timebase

        if audioFrame.duration == 0 {
            let size = (Double(MemoryLayout<Float32>.size) * Double(channelCount) * samplingRate)
            audioFrame.duration = Double(audioFrame.size) / size
        }

        let numberOfElements = numberOfFrames * Int(channelCount)
        audioFrame.setSamplesLength(numberOfElements * MemoryLayout<Float32>.size)

        var scale: Float32 = 1.0 / Float32(Int16.max)
        let audioDataPointer = audioDataBuffer.bindMemory(to: Int16.self, capacity: numberOfElements)
        vDSP_vflt16(audioDataPointer, 1, audioFrame.samples!, 1, vDSP_Length(numberOfElements))
        vDSP_vsmul(audioFrame.samples!, 1, &scale, audioFrame.samples!, 1, vDSP_Length(numberOfElements))

        return audioFrame
    }

    private func reloadAudioOutputInfo() {
        delegate?.audioDecoder(self, samplingRate: &samplingRate)
        delegate?.audioDecoder(self, channelCount: &channelCount)
    }

    deinit {
        if audioSwrBuffer != nil {
            free(audioSwrBuffer)
            audioSwrBuffer = nil
            audioSwrBufferSize = 0
        }
        if audioSwrContext != nil {
            swr_free(&audioSwrContext)
        }
        if tempFrame != nil {
            av_frame_free(&tempFrame)
        }
        IRPlayerLog("IRFFAudioDecoder release")
    }
}
