//
//  IRFFAudioDecoder.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/18.
//

import Foundation
import Accelerate
import IRFFMpeg
import IRPlayerObjc

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
        guard let outputInfo = Self.swrOutputInfo(samplingRate: samplingRate, channelCount: channelCount),
              let inputInfo = Self.swrInputInfo(from: codecContext) else { return }

        audioSwrContext = swr_alloc_set_opts(nil, av_get_default_channel_layout(outputInfo.channelCount), AV_SAMPLE_FMT_S16, outputInfo.samplingRate, av_get_default_channel_layout(inputInfo.channelCount), inputInfo.sampleFormat, inputInfo.samplingRate, 0, nil)

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

    static func sampleElementCount(numberOfFrames: Int, channelCount: UInt32) -> Int? {
        return IRFFAudioDecoderPolicy.sampleElementCount(numberOfFrames: numberOfFrames, channelCount: channelCount)
    }

    static func sampleByteCount(numberOfElements: Int) -> Int? {
        return IRFFAudioDecoderPolicy.sampleByteCount(numberOfElements: numberOfElements)
    }

    static func fallbackDuration(sampleByteCount: Int, channelCount: UInt32, samplingRate: Float64) -> TimeInterval? {
        return IRFFAudioDecoderPolicy.fallbackDuration(
            sampleByteCount: sampleByteCount,
            channelCount: channelCount,
            samplingRate: samplingRate
        )
    }

    static func swrOutputInfo(samplingRate: Float64, channelCount: UInt32) -> (samplingRate: Int32, channelCount: Int32)? {
        return IRFFAudioDecoderPolicy.swrOutputInfo(samplingRate: samplingRate, channelCount: channelCount)
    }

    static func swrInputInfo(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> (samplingRate: Int32, channelCount: Int32, sampleFormat: AVSampleFormat)? {
        return IRFFAudioDecoderPolicy.swrInputInfo(from: codecContext)
    }

    static func decodedFrameDuration(ticks: Int64, timebase: TimeInterval, fallbackDuration: TimeInterval?) -> TimeInterval {
        return IRFFAudioDecoderPolicy.decodedFrameDuration(
            ticks: ticks,
            timebase: timebase,
            fallbackDuration: fallbackDuration
        )
    }

    static func resampleRatio(outputSamplingRate: Float64, inputSamplingRate: Int32, outputChannelCount: UInt32, inputChannelCount: Int32) -> Int? {
        return IRFFAudioDecoderPolicy.resampleRatio(
            outputSamplingRate: outputSamplingRate,
            inputSamplingRate: inputSamplingRate,
            outputChannelCount: outputChannelCount,
            inputChannelCount: inputChannelCount
        )
    }

    static func resampleFrameCapacity(inputFrameCount: Int32, ratio: Int) -> Int32? {
        return IRFFAudioDecoderPolicy.resampleFrameCapacity(inputFrameCount: inputFrameCount, ratio: ratio)
    }

    static func inputChannelCapacity(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> Int? {
        return IRFFAudioDecoderPolicy.inputChannelCapacity(from: codecContext)
    }

    static func audioDataBuffer(fromSwrBuffer swrBuffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        return IRFFAudioDecoderPolicy.audioDataBuffer(fromSwrBuffer: swrBuffer)
    }

    static func audioDataBuffer(fromDecodedData decodedData: UnsafeMutablePointer<UInt8>?) -> UnsafeMutableRawPointer? {
        return IRFFAudioDecoderPolicy.audioDataBuffer(fromDecodedData: decodedData)
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        return IRFFAudioDecoderPolicy.packetDecodeResultIsFailure(result)
    }

    static func shouldDecodePacket(hasData: Bool) -> Bool {
        return IRFFAudioDecoderPolicy.shouldDecodePacket(hasData: hasData)
    }

    static func shouldDecodeFrame(hasFrame: Bool, hasPrimaryData: Bool) -> Bool {
        return IRFFAudioDecoderPolicy.shouldDecodeFrame(hasFrame: hasFrame, hasPrimaryData: hasPrimaryData)
    }

    static func canUseDirectOutput(sampleFormat: AVSampleFormat) -> Bool {
        return IRFFAudioDecoderPolicy.canUseDirectOutput(sampleFormat: sampleFormat)
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
        if !Self.shouldDecodePacket(hasData: packet.data != nil) { return 0 }

        var result = avcodec_send_packet(codecContext, &packet)
        if Self.packetDecodeResultIsFailure(result) {
            return -1
        }

        while result >= 0 {
            result = avcodec_receive_frame(codecContext, tempFrame)
            if result < 0 {
                if Self.packetDecodeResultIsFailure(result) {
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
        guard Self.shouldDecodeFrame(hasFrame: tempFrame != nil, hasPrimaryData: tempFrame?.pointee.data.0 != nil),
              let tempFrame else {
            return nil
        }

        reloadAudioOutputInfo()

        var numberOfFrames: Int
        var audioDataBuffer: UnsafeMutableRawPointer

        if let audioSwrContext = audioSwrContext {
            guard let outputInfo = Self.swrOutputInfo(samplingRate: samplingRate, channelCount: channelCount),
                  let ratio = Self.resampleRatio(outputSamplingRate: samplingRate,
                                                 inputSamplingRate: codecContext?.pointee.sample_rate ?? 0,
                                                 outputChannelCount: channelCount,
                                                 inputChannelCount: codecContext?.pointee.channels ?? 0),
                  let frameCapacity = Self.resampleFrameCapacity(inputFrameCount: tempFrame.pointee.nb_samples, ratio: ratio) else {
                return nil
            }
            let bufferSize = av_samples_get_buffer_size(nil, outputInfo.channelCount, frameCapacity, AV_SAMPLE_FMT_S16, 1)
            guard bufferSize > 0 else { return nil }

            if audioSwrBuffer == nil || audioSwrBufferSize < bufferSize {
                let requestedBufferSize = Int(bufferSize)
                guard let newBuffer = realloc(audioSwrBuffer, requestedBufferSize) else { return nil }
                audioSwrBuffer = newBuffer
                audioSwrBufferSize = requestedBufferSize
            }

            var outputBuffer: [UnsafeMutablePointer<UInt8>?] = [audioSwrBuffer?.assumingMemoryBound(to: UInt8.self), nil]
            guard let inputChannelCapacity = Self.inputChannelCapacity(from: codecContext) else { return nil }
            let inputPointer: UnsafeMutablePointer<UnsafePointer<UInt8>?> = withUnsafeMutablePointer(to: &tempFrame.pointee.data) {
                $0.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: inputChannelCapacity) {
                    $0
                }
            }

            numberOfFrames = Int(swr_convert(audioSwrContext, &outputBuffer, frameCapacity, inputPointer, tempFrame.pointee.nb_samples))
            let error: Error? = IRFFCheckError(Int32(numberOfFrames))
            if error != nil {
                IRFFErrorLog("audio codec error : \(String(describing: error))")
                return nil
            }
            guard let swrBuffer = Self.audioDataBuffer(fromSwrBuffer: audioSwrBuffer) else { return nil }
            audioDataBuffer = swrBuffer
        } else {
            if !Self.canUseDirectOutput(sampleFormat: codecContext?.pointee.sample_fmt ?? AV_SAMPLE_FMT_NONE) {
                IRFFErrorLog("audio format error")
                return nil
            }
            guard let decodedDataBuffer = Self.audioDataBuffer(fromDecodedData: tempFrame.pointee.data.0) else { return nil }
            audioDataBuffer = decodedDataBuffer
            numberOfFrames = Int(tempFrame.pointee.nb_samples)
        }

        guard let audioFrame = framePool.getUnuseFrame() as? IRFFAudioFrame else {
            return nil
        }
        
        audioFrame.position = IRFFFrameTime.position(timestamp: tempFrame.pointee.best_effort_timestamp, timebase: timebase)

        guard let numberOfElements = Self.sampleElementCount(numberOfFrames: numberOfFrames, channelCount: channelCount) else {
            return nil
        }
        guard let sampleByteCount = Self.sampleByteCount(numberOfElements: numberOfElements) else {
            return nil
        }
        audioFrame.setSamplesLength(sampleByteCount)
        let fallbackDuration = Self.fallbackDuration(sampleByteCount: sampleByteCount, channelCount: channelCount, samplingRate: samplingRate)
        audioFrame.duration = Self.decodedFrameDuration(ticks: tempFrame.pointee.duration, timebase: timebase, fallbackDuration: fallbackDuration)
        guard let samples = audioFrame.samples else { return nil }

        var scale: Float32 = 1.0 / Float32(Int16.max)
        let audioDataPointer = audioDataBuffer.bindMemory(to: Int16.self, capacity: numberOfElements)
        vDSP_vflt16(audioDataPointer, 1, samples, 1, vDSP_Length(numberOfElements))
        vDSP_vsmul(samples, 1, &scale, samples, 1, vDSP_Length(numberOfElements))

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
