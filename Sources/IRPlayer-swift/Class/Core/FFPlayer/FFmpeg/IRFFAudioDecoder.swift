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
    private let codecContext:
        UnsafeMutablePointer<AVCodecContext>
    private let decodeFrame: IRFFDecodeFrame?
    private let timebase: TimeInterval
    private var samplingRate: Float64 = 0
    private var channelCount: UInt32 = 0
    private var resampleSession: IRFFAudioResampleSession?

    private let frameQueue: IRFFFrameQueue
    private let framePool: IRFFFramePool

    static func decoder(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, delegate: IRFFAudioDecoderDelegate) -> IRFFAudioDecoder {
        return IRFFAudioDecoder(codecContext: codecContext, timebase: timebase, delegate: delegate)
    }

    private init(codecContext: UnsafeMutablePointer<AVCodecContext>, timebase: TimeInterval, delegate: IRFFAudioDecoderDelegate) {
        self.codecContext = codecContext
        self.decodeFrame = IRFFDecodeFrame()
        self.timebase = timebase
        self.delegate = delegate
        self.frameQueue = IRFFFrameQueue()
        self.framePool = IRFFFramePool.audioPool()
        setupResampler()
    }

    private func setupResampler() {
        reloadAudioOutputInfo()
        updateResampler()
    }

    private func updateResampler() {
        guard let outputInfo = Self.swrOutputInfo(samplingRate: samplingRate, channelCount: channelCount),
              let inputInfo = Self.swrInputInfo(from: codecContext),
              codecContext.pointee.ch_layout.nb_channels > 0 else {
            resampleSession = nil
            return
        }

        let setup = IRFFAudioResampleSetup(
            outputSamplingRate:
                outputInfo.samplingRate,
            outputChannelCount:
                outputInfo.channelCount,
            inputSamplingRate:
                inputInfo.samplingRate,
            inputChannelLayout:
                codecContext.pointee.ch_layout,
            inputSampleFormat:
                inputInfo.sampleFormat
        )
        guard resampleSession?.matches(setup)
                != true else {
            return
        }
        resampleSession =
            IRFFAudioResampleSession(setup: setup)
    }

    func size() -> Int {
        return Int(frameQueue.size)
    }

    func isEmpty() -> Bool {
        return frameQueue.count <= 0
    }

    static func sampleElementCount(numberOfFrames: Int, channelCount: UInt32) -> Int? {
        guard numberOfFrames > 0, channelCount > 0 else {
            return nil
        }
        let (count, overflow) =
            numberOfFrames.multipliedReportingOverflow(
                by: Int(channelCount)
            )
        return overflow ? nil : count
    }

    static func sampleByteCount(numberOfElements: Int) -> Int? {
        guard numberOfElements > 0 else { return nil }
        let (byteCount, overflow) =
            numberOfElements.multipliedReportingOverflow(
                by: MemoryLayout<Float>.size
            )
        return overflow ? nil : byteCount
    }

    static func fallbackDuration(sampleByteCount: Int, channelCount: UInt32, samplingRate: Float64) -> TimeInterval? {
        guard sampleByteCount > 0,
              channelCount > 0,
              samplingRate.isFinite,
              samplingRate > 0 else {
            return nil
        }

        let bytesPerSecond =
            Double(MemoryLayout<Float32>.size) *
            Double(channelCount) *
            samplingRate
        guard bytesPerSecond.isFinite,
              bytesPerSecond > 0 else {
            return nil
        }

        let duration =
            Double(sampleByteCount) / bytesPerSecond
        return duration.isFinite && duration > 0
            ? duration
            : nil
    }

    static func swrOutputInfo(samplingRate: Float64, channelCount: UInt32) -> (samplingRate: Int32, channelCount: Int32)? {
        guard samplingRate.isFinite,
              samplingRate > 0,
              samplingRate <= Float64(Int32.max),
              channelCount > 0,
              channelCount <= UInt32(Int32.max) else {
            return nil
        }
        return (
            Int32(samplingRate),
            Int32(channelCount)
        )
    }

    static func swrInputInfo(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> (samplingRate: Int32, channelCount: Int32, sampleFormat: AVSampleFormat)? {
        guard let codecContext else { return nil }
        let samplingRate = codecContext.pointee.sample_rate
        let channelCount =
            codecContext.pointee.ch_layout.nb_channels
        let sampleFormat = codecContext.pointee.sample_fmt
        guard samplingRate > 0,
              channelCount > 0,
              sampleFormat != AV_SAMPLE_FMT_NONE else {
            return nil
        }
        return (
            samplingRate,
            channelCount,
            sampleFormat
        )
    }

    static func decodedFrameDuration(ticks: Int64, timebase: TimeInterval, fallbackDuration: TimeInterval?) -> TimeInterval {
        if ticks > 0, timebase.isFinite, timebase > 0 {
            let duration = Double(ticks) * timebase
            if duration.isFinite, duration > 0 {
                return duration
            }
        }
        guard let fallbackDuration,
              fallbackDuration.isFinite,
              fallbackDuration > 0 else {
            return 0
        }
        return fallbackDuration
    }

    static func resampleRatio(outputSamplingRate: Float64, inputSamplingRate: Int32, outputChannelCount: UInt32, inputChannelCount: Int32) -> Int? {
        guard outputSamplingRate.isFinite,
              outputSamplingRate > 0,
              inputSamplingRate > 0,
              outputChannelCount > 0,
              inputChannelCount > 0 else {
            return nil
        }

        let samplingRatioValue =
            outputSamplingRate / Float64(inputSamplingRate)
        guard samplingRatioValue.isFinite,
              samplingRatioValue < Float64(Int.max) else {
            return nil
        }
        let samplingRatio =
            max(1, Int(ceil(samplingRatioValue)))

        let inputChannels = Int(inputChannelCount)
        let (channelNumerator, channelOverflow) =
            Int(outputChannelCount).addingReportingOverflow(
                inputChannels - 1
            )
        guard !channelOverflow else { return nil }
        let channelRatio =
            max(1, channelNumerator / inputChannels)

        let (audioRatio, audioOverflow) =
            samplingRatio.multipliedReportingOverflow(
                by: channelRatio
            )
        guard !audioOverflow else { return nil }
        let (ratio, ratioOverflow) =
            audioRatio.multipliedReportingOverflow(by: 2)
        guard !ratioOverflow, ratio > 0 else {
            return nil
        }
        return ratio
    }

    static func resampleFrameCapacity(inputFrameCount: Int32, ratio: Int) -> Int32? {
        guard inputFrameCount > 0,
              ratio > 0,
              ratio <= Int(Int32.max) else {
            return nil
        }
        let (capacity, overflow) =
            Int(inputFrameCount).multipliedReportingOverflow(
                by: ratio
            )
        guard !overflow,
              capacity > 0,
              capacity <= Int(Int32.max) else {
            return nil
        }
        return Int32(capacity)
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        return IRFFDecodeResult.isFailure(result)
    }

    static func shouldDecodePacket(hasData: Bool) -> Bool {
        return hasData
    }

    static func shouldDecodeFrame(hasFrame: Bool, hasPrimaryData: Bool) -> Bool {
        return hasFrame && hasPrimaryData
    }

    static func canUseDirectOutput(sampleFormat: AVSampleFormat) -> Bool {
        return sampleFormat == AV_SAMPLE_FMT_S16
    }

    func duration() -> TimeInterval {
        return frameQueue.duration
    }

    func flush() {
        frameQueue.flush()
        framePool.flush()
        avcodec_flush_buffers(codecContext)
    }

    func destroy() {
        frameQueue.close()
        framePool.close()
    }

    func waitForFrame() -> IRFFAudioFrame? {
        return frameQueue.waitForFrame() as? IRFFAudioFrame
    }

    func dequeueFrame() -> IRFFAudioFrame? {
        return frameQueue.dequeue() as? IRFFAudioFrame
    }

    func putPacket(_ packet: IRFFPacket) -> Int {
        defer { packet.close() }
        guard let snapshot = packet.snapshot,
              Self.shouldDecodePacket(
                  hasData: snapshot.hasData
              ) else {
            return 0
        }

        var decodeResult = -1
        let didBorrow = packet.withPacket {
            borrowedPacket in
            decodeResult = decodePacket(borrowedPacket)
            return true
        }
        return didBorrow ? decodeResult : -1
    }

    private func decodePacket(
        _ borrowedPacket: AVPacket
    ) -> Int {
        var borrowedPacket = borrowedPacket
        var result = avcodec_send_packet(
            codecContext,
            &borrowedPacket
        )
        if Self.packetDecodeResultIsFailure(result) {
            return -1
        }

        while result >= 0 {
            guard let decodeFrame else { return -1 }
            var receivedFrame:
                IRFFAudioFrame?
            var receiveResult: Int32 = -1
            let didBorrow = decodeFrame.withFrame {
                frame in
                receiveResult = avcodec_receive_frame(
                    codecContext,
                    frame
                )
                if receiveResult >= 0 {
                    receivedFrame = autoreleasepool {
                        decode(frame: frame)
                    }
                }
                return true
            }
            guard didBorrow else { return -1 }
            result = receiveResult
            if result < 0 {
                if Self.packetDecodeResultIsFailure(result) {
                    return -1
                }
                break
            }
            if let receivedFrame {
                frameQueue.enqueue(receivedFrame)
            }
        }
        return 0
    }

    private func decode(
        frame decodedFrame:
            UnsafeMutablePointer<AVFrame>
    ) -> IRFFAudioFrame? {
        guard Self.shouldDecodeFrame(
            hasFrame: true,
            hasPrimaryData:
                decodedFrame.pointee.data.0 != nil
        ) else {
            return nil
        }

        reloadAudioOutputInfo()
        updateResampler()
        guard let audioFrame =
                framePool.leaseFrame()
                    as? IRFFAudioFrame else {
            return nil
        }
        var didPopulateFrame = false
        defer {
            if !didPopulateFrame {
                audioFrame.cancel()
            }
        }

        if let resampleSession {
            guard Self.swrOutputInfo(
                samplingRate: samplingRate,
                channelCount: channelCount
            ) != nil,
                  let ratio = Self.resampleRatio(outputSamplingRate: samplingRate,
                                                 inputSamplingRate: codecContext.pointee.sample_rate,
                                                 outputChannelCount: channelCount,
                                                 inputChannelCount: codecContext.pointee.ch_layout.nb_channels),
                  let frameCapacity = Self.resampleFrameCapacity(inputFrameCount: decodedFrame.pointee.nb_samples, ratio: ratio) else {
                return nil
            }
            let outcome =
                resampleSession.withConvertedSamples(
                    from: decodedFrame,
                    outputFrameCapacity:
                        frameCapacity
                ) { samples, numberOfFrames in
                    populate(
                        audioFrame,
                        from: samples,
                        numberOfFrames:
                            numberOfFrames,
                        decodedFrame:
                            decodedFrame
                    )
                }
            if case let .ffmpegError(code) = outcome {
                let error: Error? =
                    IRFFCheckError(code)
                IRFFErrorLog(
                    "audio codec error : "
                        + "\(String(describing: error))"
                )
            }
            guard case .converted = outcome else {
                return nil
            }
        } else {
            if !Self.canUseDirectOutput(sampleFormat: codecContext.pointee.sample_fmt) {
                IRFFErrorLog("audio format error")
                return nil
            }
            guard let decodedData =
                    decodedFrame.pointee.data.0,
                  let numberOfElements =
                    Self.sampleElementCount(
                        numberOfFrames:
                            Int(
                                decodedFrame
                                    .pointee.nb_samples
                            ),
                        channelCount: channelCount
                    ) else {
                return nil
            }
            let samples = UnsafeBufferPointer(
                start: UnsafeRawPointer(decodedData)
                    .assumingMemoryBound(
                        to: Int16.self
                    ),
                count: numberOfElements
            )
            guard populate(
                audioFrame,
                from: samples,
                numberOfFrames:
                    Int(
                        decodedFrame
                            .pointee.nb_samples
                    ),
                decodedFrame: decodedFrame
            ) else {
                return nil
            }
        }

        didPopulateFrame = true
        return audioFrame
    }

    private func populate(
        _ audioFrame: IRFFAudioFrame,
        from inputSamples:
            UnsafeBufferPointer<Int16>,
        numberOfFrames: Int,
        decodedFrame:
            UnsafeMutablePointer<AVFrame>
    ) -> Bool {
        guard let numberOfElements =
                Self.sampleElementCount(
                    numberOfFrames: numberOfFrames,
                    channelCount: channelCount
                ),
              numberOfElements
                == inputSamples.count,
              let sampleByteCount =
                Self.sampleByteCount(
                    numberOfElements:
                        numberOfElements
                ),
              let inputBaseAddress =
                inputSamples.baseAddress else {
            return false
        }

        audioFrame.setSamplesLength(sampleByteCount)
        var scale:
            Float32 = 1.0 / Float32(Int16.max)
        guard audioFrame.activeSampleCount
                == numberOfElements,
              audioFrame.withMutableSamples({
                  samples in
                  guard let baseAddress =
                          samples.baseAddress else {
                      return false
                  }
                  vDSP_vflt16(
                      inputBaseAddress,
                      1,
                      baseAddress,
                      1,
                      vDSP_Length(numberOfElements)
                  )
                  vDSP_vsmul(
                      baseAddress,
                      1,
                      &scale,
                      baseAddress,
                      1,
                      vDSP_Length(numberOfElements)
                  )
                  return true
              }) else {
            return false
        }

        audioFrame.position = IRFFFrameTime.position(
            timestamp:
                decodedFrame
                    .pointee.best_effort_timestamp,
            timebase: timebase
        )
        let fallbackDuration = Self.fallbackDuration(
            sampleByteCount: sampleByteCount,
            channelCount: channelCount,
            samplingRate: samplingRate
        )
        audioFrame.duration =
            Self.decodedFrameDuration(
                ticks: decodedFrame.pointee.duration,
                timebase: timebase,
                fallbackDuration: fallbackDuration
            )
        return true
    }

    private func reloadAudioOutputInfo() {
        delegate?.audioDecoder(self, samplingRate: &samplingRate)
        delegate?.audioDecoder(self, channelCount: &channelCount)
    }

    deinit {
        IRPlayerLog("IRFFAudioDecoder release")
    }
}
