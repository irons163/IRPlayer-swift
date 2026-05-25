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

    static func sampleElementCount(numberOfFrames: Int, channelCount: UInt32) -> Int? {
        guard numberOfFrames > 0, channelCount > 0 else { return nil }
        let (count, overflow) = numberOfFrames.multipliedReportingOverflow(by: Int(channelCount))
        guard !overflow else { return nil }
        return count
    }

    static func sampleByteCount(numberOfElements: Int) -> Int? {
        guard numberOfElements > 0 else { return nil }
        let (byteCount, overflow) = numberOfElements.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !overflow else { return nil }
        return byteCount
    }

    static func fallbackDuration(sampleByteCount: Int, channelCount: UInt32, samplingRate: Float64) -> TimeInterval? {
        guard sampleByteCount > 0,
              channelCount > 0,
              samplingRate.isFinite,
              samplingRate > 0 else {
            return nil
        }

        let bytesPerSecond = Double(MemoryLayout<Float32>.size) * Double(channelCount) * samplingRate
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }

        let duration = Double(sampleByteCount) / bytesPerSecond
        return duration.isFinite && duration > 0 ? duration : nil
    }

    static func resampleRatio(outputSamplingRate: Float64, inputSamplingRate: Int32, outputChannelCount: UInt32, inputChannelCount: Int32) -> Int? {
        guard outputSamplingRate.isFinite,
              outputSamplingRate > 0,
              inputSamplingRate > 0,
              outputChannelCount > 0,
              inputChannelCount > 0 else {
            return nil
        }

        let inputSamplingRateValue = Float64(inputSamplingRate)
        let samplingRatioValue = outputSamplingRate / inputSamplingRateValue
        guard samplingRatioValue.isFinite, samplingRatioValue < Float64(Int.max) else { return nil }

        let samplingRatio = max(1, Int(ceil(samplingRatioValue)))
        let inputChannels = Int(inputChannelCount)
        let (roundedChannelNumerator, channelNumeratorOverflow) = Int(outputChannelCount).addingReportingOverflow(inputChannels - 1)
        guard !channelNumeratorOverflow else { return nil }
        let channelRatio = max(1, roundedChannelNumerator / inputChannels)
        let (audioRatio, audioRatioOverflow) = samplingRatio.multipliedReportingOverflow(by: channelRatio)
        guard !audioRatioOverflow else { return nil }

        let (ratio, ratioOverflow) = audioRatio.multipliedReportingOverflow(by: 2)
        guard !ratioOverflow, ratio > 0 else { return nil }
        return ratio
    }

    static func resampleFrameCapacity(inputFrameCount: Int32, ratio: Int) -> Int32? {
        guard inputFrameCount > 0, ratio > 0, ratio <= Int(Int32.max) else { return nil }

        let (capacity, overflow) = Int(inputFrameCount).multipliedReportingOverflow(by: ratio)
        guard !overflow, capacity > 0, capacity <= Int(Int32.max) else { return nil }
        return Int32(capacity)
    }

    static func inputChannelCapacity(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> Int? {
        guard let channels = codecContext?.pointee.channels, channels > 0 else { return nil }
        return Int(channels)
    }

    static func audioDataBuffer(fromSwrBuffer swrBuffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let swrBuffer else { return nil }
        return swrBuffer
    }

    static func audioDataBuffer(fromDecodedData decodedData: UnsafeMutablePointer<UInt8>?) -> UnsafeMutableRawPointer? {
        guard let decodedData else { return nil }
        return UnsafeMutableRawPointer(decodedData)
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
            guard let ratio = Self.resampleRatio(outputSamplingRate: samplingRate,
                                                 inputSamplingRate: codecContext?.pointee.sample_rate ?? 0,
                                                 outputChannelCount: channelCount,
                                                 inputChannelCount: codecContext?.pointee.channels ?? 0),
                  let frameCapacity = Self.resampleFrameCapacity(inputFrameCount: tempFrame.pointee.nb_samples, ratio: ratio) else {
                return nil
            }
            let bufferSize = av_samples_get_buffer_size(nil, Int32(channelCount), frameCapacity, AV_SAMPLE_FMT_S16, 1)
            guard bufferSize > 0 else { return nil }

            if audioSwrBuffer == nil || audioSwrBufferSize < bufferSize {
                let requestedBufferSize = Int(bufferSize)
                guard let newBuffer = realloc(audioSwrBuffer, requestedBufferSize) else { return nil }
                audioSwrBuffer = newBuffer
                audioSwrBufferSize = requestedBufferSize
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
            if codecContext?.pointee.sample_fmt != AV_SAMPLE_FMT_S16 {
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
        
        audioFrame.position = Double(tempFrame.pointee.best_effort_timestamp) * timebase
        audioFrame.duration = Double(tempFrame.pointee.duration) * timebase

        guard let numberOfElements = Self.sampleElementCount(numberOfFrames: numberOfFrames, channelCount: channelCount) else {
            return nil
        }
        guard let sampleByteCount = Self.sampleByteCount(numberOfElements: numberOfElements) else {
            return nil
        }
        audioFrame.setSamplesLength(sampleByteCount)
        if audioFrame.duration == 0,
           let fallbackDuration = Self.fallbackDuration(sampleByteCount: sampleByteCount, channelCount: channelCount, samplingRate: samplingRate) {
            audioFrame.duration = fallbackDuration
        }
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
