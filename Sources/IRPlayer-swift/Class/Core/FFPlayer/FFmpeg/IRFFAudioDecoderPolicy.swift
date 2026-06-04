import Foundation
import IRFFMpeg
import IRPlayerObjc

enum IRFFAudioDecoderPolicy {

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

    static func swrOutputInfo(samplingRate: Float64, channelCount: UInt32) -> (samplingRate: Int32, channelCount: Int32)? {
        guard samplingRate.isFinite,
              samplingRate > 0,
              samplingRate <= Float64(Int32.max),
              channelCount > 0,
              channelCount <= UInt32(Int32.max) else {
            return nil
        }

        return (Int32(samplingRate), Int32(channelCount))
    }

    static func swrInputInfo(from codecContext: UnsafeMutablePointer<AVCodecContext>?) -> (samplingRate: Int32, channelCount: Int32, sampleFormat: AVSampleFormat)? {
        guard let codecContext else { return nil }

        let samplingRate = codecContext.pointee.sample_rate
        let channelCount = codecContext.pointee.channels
        let sampleFormat = codecContext.pointee.sample_fmt
        guard samplingRate > 0,
              channelCount > 0,
              sampleFormat != AV_SAMPLE_FMT_NONE else {
            return nil
        }

        return (samplingRate, channelCount, sampleFormat)
    }

    static func decodedFrameDuration(ticks: Int64, timebase: TimeInterval, fallbackDuration: TimeInterval?) -> TimeInterval {
        if ticks > 0, timebase.isFinite, timebase > 0 {
            let duration = Double(ticks) * timebase
            if duration.isFinite, duration > 0 {
                return duration
            }
        }

        guard let fallbackDuration, fallbackDuration.isFinite, fallbackDuration > 0 else {
            return 0
        }
        return fallbackDuration
    }

    static func resampleRatio(outputSamplingRate: Float64,
                              inputSamplingRate: Int32,
                              outputChannelCount: UInt32,
                              inputChannelCount: Int32) -> Int? {
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

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        guard result < 0 else { return false }
        return result != AVERROR(EAGAIN) && result != IR_AVERROR_EOF
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
}
