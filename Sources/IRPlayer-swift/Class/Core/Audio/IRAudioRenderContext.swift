import Accelerate
import AVFoundation
import Foundation

final class IRAudioRenderContext: @unchecked Sendable {
    static let defaultMaximumFrames: UInt32 = 4_096
    static let defaultMaximumChannels: UInt32 = 8

    struct Diagnostics {
        let active: Bool
        let hasOwner: Bool
        let hasDelegate: Bool
        let sampleRate: Float64
        let channelCount: UInt32
        let maximumFrames: UInt32
        let maximumChannels: UInt32
    }

    private let renderLock = NSLock()
    private let maximumFrames: UInt32
    private let maximumChannels: UInt32
    private let maximumSampleCount: Int
    private let scratch: UnsafeMutablePointer<Float>

    private weak var owner: IRAudioManager?
    private weak var delegate: IRAudioManagerDelegate?
    private var format = AudioStreamBasicDescription()
    private var active = false

    init(
        maximumFrames: UInt32 = defaultMaximumFrames,
        maximumChannels: UInt32 = defaultMaximumChannels
    ) {
        precondition(maximumFrames > 0)
        precondition(maximumChannels > 0)
        guard let sampleCount = Self.sampleCount(
            numberOfFrames: maximumFrames,
            numberOfChannels: maximumChannels
        ) else {
            preconditionFailure("Audio render capacity overflow")
        }
        self.maximumFrames = maximumFrames
        self.maximumChannels = maximumChannels
        maximumSampleCount = sampleCount
        scratch = .allocate(capacity: sampleCount)
        scratch.initialize(repeating: 0, count: sampleCount)
    }

    deinit {
        scratch.deinitialize(count: maximumSampleCount)
        scratch.deallocate()
    }

    var diagnostics: Diagnostics {
        renderLock.lock()
        defer { renderLock.unlock() }
        return Diagnostics(
            active: active,
            hasOwner: owner != nil,
            hasDelegate: delegate != nil,
            sampleRate: format.mSampleRate,
            channelCount: format.mChannelsPerFrame,
            maximumFrames: maximumFrames,
            maximumChannels: maximumChannels
        )
    }

    var currentDelegate: IRAudioManagerDelegate? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return delegate
    }

    func configure(format: AudioStreamBasicDescription) {
        renderLock.lock()
        self.format = format
        renderLock.unlock()
    }

    func activate(
        owner: IRAudioManager,
        delegate: IRAudioManagerDelegate
    ) {
        renderLock.lock()
        self.owner = owner
        self.delegate = delegate
        active = true
        renderLock.unlock()
    }

    func deactivate() {
        renderLock.lock()
        active = false
        owner = nil
        delegate = nil
        renderLock.unlock()
    }

    func renderFrames(
        _ numberOfFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let ioData else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        Self.silence(buffers)

        guard renderLock.try() else { return noErr }
        defer { renderLock.unlock() }

        guard active,
              let owner,
              let delegate,
              numberOfFrames > 0,
              numberOfFrames <= maximumFrames,
              Self.supportedPCMFormat(
                format,
                maximumChannels: maximumChannels
              ),
              let sampleCount = Self.sampleCount(
                numberOfFrames: numberOfFrames,
                numberOfChannels: format.mChannelsPerFrame
              ),
              sampleCount <= maximumSampleCount else {
            return noErr
        }

        memset(
            scratch,
            0,
            sampleCount * MemoryLayout<Float>.stride
        )
        delegate.audioManager(
            owner,
            outputData: scratch,
            numberOfFrames: numberOfFrames,
            numberOfChannels: format.mChannelsPerFrame
        )

        copyScratch(
            to: buffers,
            numberOfFrames: numberOfFrames,
            sampleCount: sampleCount
        )
        return noErr
    }

    static func sampleCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32
    ) -> Int? {
        guard numberOfFrames > 0, numberOfChannels > 0 else { return nil }
        let (count, overflow) = Int(numberOfFrames)
            .multipliedReportingOverflow(by: Int(numberOfChannels))
        guard !overflow, count > 0 else { return nil }
        return count
    }

    static func sampleCount(
        numberOfFrames: UInt32,
        numberOfChannels: UInt32,
        maximumSampleCount: Int
    ) -> Int? {
        guard maximumSampleCount > 0,
              let count = sampleCount(
                numberOfFrames: numberOfFrames,
                numberOfChannels: numberOfChannels
              ),
              count <= maximumSampleCount else {
            return nil
        }
        return count
    }

    static func supportedPCMFormat(
        _ format: AudioStreamBasicDescription,
        maximumChannels: UInt32 = defaultMaximumChannels
    ) -> Bool {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate.isFinite,
              format.mSampleRate > 0,
              format.mChannelsPerFrame > 0,
              format.mChannelsPerFrame <= maximumChannels,
              format.mFramesPerPacket == 1,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            return false
        }

        let bytesPerSample: UInt32
        if format.mBitsPerChannel == 32 {
            guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags &
                    kAudioFormatFlagIsSignedInteger == 0 else {
                return false
            }
            bytesPerSample = 4
        } else if format.mBitsPerChannel == 16 {
            guard format.mFormatFlags &
                    kAudioFormatFlagIsSignedInteger != 0,
                  format.mFormatFlags & kAudioFormatFlagIsFloat == 0 else {
                return false
            }
            bytesPerSample = 2
        } else {
            return false
        }

        let expectedBytesPerFrame =
            format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            ? bytesPerSample
            : bytesPerSample * format.mChannelsPerFrame
        return format.mBytesPerFrame == expectedBytesPerFrame &&
            format.mBytesPerPacket == expectedBytesPerFrame
    }

    private func copyScratch(
        to buffers: UnsafeMutableAudioBufferListPointer,
        numberOfFrames: UInt32,
        sampleCount: Int
    ) {
        let outputChannels = Int(format.mChannelsPerFrame)
        let bytesPerSample = Int(format.mBitsPerChannel / 8)
        guard outputChannels > 0, bytesPerSample == 2 || bytesPerSample == 4
        else {
            return
        }

        if bytesPerSample == 2 {
            var low: Float = -1
            var high: Float = 1
            vDSP_vclip(
                scratch,
                1,
                &low,
                &high,
                scratch,
                1,
                vDSP_Length(sampleCount)
            )
            var scale = Float(Int16.max)
            vDSP_vsmul(
                scratch,
                1,
                &scale,
                scratch,
                1,
                vDSP_Length(sampleCount)
            )
        }

        var sourceChannelOffset = 0
        for buffer in buffers {
            let bufferChannels = Int(buffer.mNumberChannels)
            defer { sourceChannelOffset += bufferChannels }
            guard bufferChannels > 0,
                  sourceChannelOffset < outputChannels,
                  let data = buffer.mData else {
                continue
            }

            let (frameSamples, sampleOverflow) = Int(numberOfFrames)
                .multipliedReportingOverflow(by: bufferChannels)
            let (requiredBytes, byteOverflow) = frameSamples
                .multipliedReportingOverflow(by: bytesPerSample)
            guard !sampleOverflow,
                  !byteOverflow,
                  requiredBytes <= Int(buffer.mDataByteSize) else {
                continue
            }

            let copyChannelCount = min(
                bufferChannels,
                outputChannels - sourceChannelOffset
            )
            for channel in 0..<copyChannelCount {
                let source = scratch + sourceChannelOffset + channel
                if bytesPerSample == 4 {
                    var zero: Float = 0
                    vDSP_vsadd(
                        source,
                        vDSP_Stride(outputChannels),
                        &zero,
                        data.assumingMemoryBound(to: Float.self) + channel,
                        vDSP_Stride(bufferChannels),
                        vDSP_Length(numberOfFrames)
                    )
                } else {
                    vDSP_vfix16(
                        source,
                        vDSP_Stride(outputChannels),
                        data.assumingMemoryBound(to: Int16.self) + channel,
                        vDSP_Stride(bufferChannels),
                        vDSP_Length(numberOfFrames)
                    )
                }
            }
        }
    }

    private static func silence(
        _ buffers: UnsafeMutableAudioBufferListPointer
    ) {
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }
}

func irAudioRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inOutputBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let context = Unmanaged<IRAudioRenderContext>
        .fromOpaque(inRefCon)
        .takeUnretainedValue()
    return context.renderFrames(inNumberFrames, ioData: ioData)
}
