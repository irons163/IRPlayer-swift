import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
#else
@_implementationOnly import IRFFMpeg
#endif

struct IRFFAudioResampleSetup {
    let outputSamplingRate: Int32
    let outputChannelCount: Int32
    let inputSamplingRate: Int32
    let inputChannelLayout: AVChannelLayout
    let inputSampleFormat: AVSampleFormat

    var configuration:
        IRFFAudioResampleConfiguration?
    {
        guard let inputChannelLayoutDescription =
                Self.channelLayoutDescription(
                    inputChannelLayout
                ) else {
            return nil
        }
        return IRFFAudioResampleConfiguration(
            outputSamplingRate:
                outputSamplingRate,
            outputChannelCount:
                outputChannelCount,
            inputSamplingRate:
                inputSamplingRate,
            inputChannelCount:
                inputChannelLayout.nb_channels,
            inputChannelLayoutDescription:
                inputChannelLayoutDescription,
            inputSampleFormat:
                inputSampleFormat
        )
    }

    private static func channelLayoutDescription(
        _ inputChannelLayout: AVChannelLayout
    ) -> String? {
        // This is a borrowed structural view. It is never uninitialized; the
        // live runtime makes an owned copy before passing it to swresample.
        var borrowedLayout = inputChannelLayout
        var buffer = [CChar](repeating: 0, count: 64)
        var result = buffer.withUnsafeMutableBufferPointer {
            output in
            withUnsafePointer(to: &borrowedLayout) {
                layout in
                av_channel_layout_describe(
                    layout,
                    output.baseAddress,
                    output.count
                )
            }
        }
        guard result >= 0 else { return nil }

        let requiredCapacity = Int(result) + 1
        if requiredCapacity > buffer.count {
            buffer = [CChar](
                repeating: 0,
                count: requiredCapacity
            )
            result = buffer.withUnsafeMutableBufferPointer {
                output in
                withUnsafePointer(to: &borrowedLayout) {
                    layout in
                    av_channel_layout_describe(
                        layout,
                        output.baseAddress,
                        output.count
                    )
                }
            }
        }
        guard result >= 0,
              Int(result) < buffer.count else {
            return nil
        }
        return buffer.withUnsafeBufferPointer {
            output in
            guard let baseAddress =
                    output.baseAddress else {
                return nil
            }
            return String(cString: baseAddress)
        }
    }
}

struct IRFFAudioResampleConfiguration:
    Equatable
{
    let outputSamplingRate: Int32
    let outputChannelCount: Int32
    let inputSamplingRate: Int32
    let inputChannelCount: Int32
    let inputChannelLayoutDescription: String
    let inputSampleFormat: AVSampleFormat
}

struct IRFFAudioResampleContextCreation {
    let result: Int32
    let context: OpaquePointer?
}

struct IRFFAudioResampleRuntime {
    let createContext: (
        IRFFAudioResampleSetup
    ) -> IRFFAudioResampleContextCreation
    let initializeContext: (OpaquePointer) -> Int32
    let outputBufferSize: (
        Int32,
        Int32
    ) -> Int32
    let convert: (
        OpaquePointer,
        UnsafeMutablePointer<UInt8>,
        Int32,
        UnsafeMutablePointer<AVFrame>,
        Int
    ) -> Int32
    let freeContext: (inout OpaquePointer?) -> Void

    static let live = IRFFAudioResampleRuntime(
        createContext: { setup in
            var outputLayout = AVChannelLayout()
            av_channel_layout_default(
                &outputLayout,
                setup.outputChannelCount
            )
            defer {
                av_channel_layout_uninit(&outputLayout)
            }

            var inputLayout = AVChannelLayout()
            // `IRFFAudioResampleSetup` borrows the codec layout. FFmpeg
            // requires a deep copy before a layout can be independently
            // initialized or uninitialized.
            var borrowedInputLayout =
                setup.inputChannelLayout
            let copyResult = withUnsafePointer(
                to: &borrowedInputLayout
            ) { source in
                av_channel_layout_copy(
                    &inputLayout,
                    source
                )
            }
            guard copyResult >= 0 else {
                return IRFFAudioResampleContextCreation(
                    result: copyResult,
                    context: nil
                )
            }
            defer {
                av_channel_layout_uninit(&inputLayout)
            }
            var context: OpaquePointer?
            let result = swr_alloc_set_opts2(
                &context,
                &outputLayout,
                AV_SAMPLE_FMT_S16,
                setup.outputSamplingRate,
                &inputLayout,
                setup.inputSampleFormat,
                setup.inputSamplingRate,
                0,
                nil
            )
            return IRFFAudioResampleContextCreation(
                result: result,
                context: context
            )
        },
        initializeContext: { context in
            swr_init(context)
        },
        outputBufferSize: {
            channelCount,
            frameCapacity in
            av_samples_get_buffer_size(
                nil,
                channelCount,
                frameCapacity,
                AV_SAMPLE_FMT_S16,
                1
            )
        },
        convert: {
            context,
            output,
            outputFrameCapacity,
            frame,
            inputChannelCapacity in
            var outputBuffers:
                [UnsafeMutablePointer<UInt8>?] = [
                    output,
                    nil
                ]
            guard let extendedData =
                    frame.pointee.extended_data else {
                return -1
            }
            return extendedData.withMemoryRebound(
                to: UnsafePointer<UInt8>?.self,
                capacity: inputChannelCapacity
            ) { inputBuffers in
                swr_convert(
                    context,
                    &outputBuffers,
                    outputFrameCapacity,
                    inputBuffers,
                    frame.pointee.nb_samples
                )
            }
        },
        freeContext: { context in
            swr_free(&context)
        }
    )
}

final class IRFFAudioResampleSession:
    @unchecked Sendable
{
    enum ConversionOutcome: Equatable {
        case converted(
            frameCount: Int,
            sampleCount: Int
        )
        case closed
        case invalidInput
        case ffmpegError(Int32)
        case consumerRejected
    }

    struct Diagnostics: Equatable {
        let closed: Bool
        let hasContext: Bool
        let sampleCapacity: Int
    }

    private let lock = NSLock()
    private let runtime: IRFFAudioResampleRuntime
    private let configuration:
        IRFFAudioResampleConfiguration
    private let outputChannelCount: Int
    private let inputChannelCapacity: Int
    private var context: OpaquePointer?
    private var samples: [Int16] = []
    private var closed = false

    init?(
        setup: IRFFAudioResampleSetup,
        runtime: IRFFAudioResampleRuntime = .live
    ) {
        guard setup.outputSamplingRate > 0,
              setup.outputChannelCount > 0,
              setup.inputSamplingRate > 0,
              setup.inputChannelLayout.nb_channels > 0,
              setup.inputSampleFormat
                != AV_SAMPLE_FMT_NONE else {
            return nil
        }

        guard let configuration =
                setup.configuration else {
            return nil
        }
        let creation = runtime.createContext(setup)
        guard creation.result >= 0,
              let context = creation.context else {
            var contextToFree = creation.context
            if contextToFree != nil {
                runtime.freeContext(&contextToFree)
            }
            return nil
        }
        let initializationResult =
            runtime.initializeContext(context)
        guard initializationResult >= 0 else {
            var contextToFree = creation.context
            runtime.freeContext(&contextToFree)
            return nil
        }

        self.runtime = runtime
        self.configuration = configuration
        outputChannelCount =
            Int(setup.outputChannelCount)
        inputChannelCapacity =
            Int(setup.inputChannelLayout.nb_channels)
        self.context = context
    }

    func matches(
        _ setup: IRFFAudioResampleSetup
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let candidate =
                setup.configuration else {
            return false
        }
        return !closed
            && configuration == candidate
    }

    var diagnostics: Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(
            closed: closed,
            hasContext: context != nil,
            sampleCapacity: samples.count
        )
    }

    func withConvertedSamples(
        from frame: UnsafeMutablePointer<AVFrame>,
        outputFrameCapacity: Int32,
        _ body: (
            UnsafeBufferPointer<Int16>,
            Int
        ) -> Bool
    ) -> ConversionOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let context else {
            return .closed
        }
        guard outputFrameCapacity > 0,
              frame.pointee.nb_samples > 0 else {
            return .invalidInput
        }

        let byteCount = runtime.outputBufferSize(
            Int32(outputChannelCount),
            outputFrameCapacity
        )
        guard byteCount >= 0 else {
            return .ffmpegError(byteCount)
        }
        guard byteCount > 0,
              byteCount % Int32(
                  MemoryLayout<Int16>.stride
              ) == 0 else {
            return .invalidInput
        }
        let sampleCapacity =
            Int(byteCount)
            / MemoryLayout<Int16>.stride
        guard sampleCapacity > 0 else {
            return .invalidInput
        }
        if samples.count < sampleCapacity {
            samples = [Int16](
                repeating: 0,
                count: sampleCapacity
            )
        }

        return samples.withUnsafeMutableBufferPointer {
            sampleBuffer in
            guard let sampleBaseAddress =
                    sampleBuffer.baseAddress else {
                return .invalidInput
            }
            let output = UnsafeMutableRawPointer(
                sampleBaseAddress
            ).assumingMemoryBound(to: UInt8.self)
            let convertedFrameCount = runtime.convert(
                context,
                output,
                outputFrameCapacity,
                frame,
                inputChannelCapacity
            )
            guard convertedFrameCount >= 0 else {
                return .ffmpegError(
                    convertedFrameCount
                )
            }
            guard convertedFrameCount > 0,
                  convertedFrameCount
                    <= outputFrameCapacity else {
                return .invalidInput
            }
            let (sampleCount, overflow) =
                Int(convertedFrameCount)
                .multipliedReportingOverflow(
                    by: outputChannelCount
                )
            guard !overflow,
                  sampleCount > 0,
                  sampleCount
                    <= sampleBuffer.count else {
                return .invalidInput
            }

            let borrowedSamples =
                UnsafeBufferPointer(
                    start: sampleBaseAddress,
                    count: sampleCount
                )
            guard body(
                borrowedSamples,
                Int(convertedFrameCount)
            ) else {
                return .consumerRejected
            }
            return .converted(
                frameCount: Int(convertedFrameCount),
                sampleCount: sampleCount
            )
        }
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }

        runtime.freeContext(&context)
        samples = []
        closed = true
        return true
    }

    deinit {
        close()
    }
}
