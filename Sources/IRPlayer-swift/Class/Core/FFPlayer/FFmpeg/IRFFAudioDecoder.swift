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
