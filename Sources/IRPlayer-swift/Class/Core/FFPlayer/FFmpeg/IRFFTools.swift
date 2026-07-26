//
//  IRFFTools.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/7/19.
//

import Foundation
#if SWIFT_PACKAGE || DEBUG
internal import IRFFMpeg
internal import IRPlayerObjc
#else
@_implementationOnly import IRFFMpeg
@_implementationOnly import IRPlayerObjc
#endif

enum IRFFDecoderErrorCode: Int {
    case formatCreate = 0
    case formatOpenInput
    case formatFindStreamInfo
    case streamNotFound
    case codecContextCreate
    case codecContextSetParam
    case codecFindDecoder
    case codecVideoSendPacket
    case codecAudioSendPacket
    case codecVideoReceiveFrame
    case codecAudioReceiveFrame
    case codecOpen2
    case audioSwrInit
    case formatReadFrame
    case formatInvalidHeaders
}

func IRFFErrorLog(_ text: String) {
    IRFFRuntimeDebugOutput.write(text)
}

func IRPlayerLog(_ text: String) {
    IRFFRuntimeDebugOutput.write(text)
}

enum IRFFRuntimeDebugOutput {
    #if IRFFFFmpegRuntimeDebugOutputEnable
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        IRPlayerImp.Logger.libraryLogger.debug(message())
    }
}

// MARK: - Utility Functions

enum IRFFLogFormatting {
    static func message(
        format: UnsafePointer<CChar>,
        args: CVaListPointer
    ) -> String? {
        guard let formatString =
            String(validatingUTF8: format) else {
            return nil
        }
        return NSString(
            format: formatString,
            arguments: args
        ) as String
    }

    static func logLine(for message: String) -> String {
        "IRFFLog: \(message)"
    }
}

enum IRFFDecodeResult {
    static func isFailure(_ result: Int32) -> Bool {
        guard result < 0 else { return false }
        return result != AVERROR(EAGAIN) &&
            result != IR_AVERROR_EOF
    }
}

enum IRFFCodecPump {
    enum Input: Equatable {
        case packet
        case drain
    }

    enum Outcome: Equatable {
        case needsInput(frameCount: Int)
        case endOfStream(frameCount: Int)
        case failed(code: Int32, frameCount: Int)
        case canceled(frameCount: Int)
    }

    private enum ReceiveStop {
        case needsInput
        case endOfStream
        case failed(Int32)
        case canceled
    }

    /// Runs one FFmpeg send/receive transaction without losing the input when
    /// `send` reports EAGAIN. The caller owns the packet and decoded frame;
    /// `didReceiveFrame` is invoked once for every successful receive.
    static func run(
        input: Input,
        send: () -> Int32,
        receive: () -> Int32,
        isGenerationCurrent: () -> Bool = { true },
        didReceiveFrame: () -> Void
    ) -> Outcome {
        var frameCount = 0

        func receiveAvailableFrames() -> ReceiveStop {
            while true {
                guard isGenerationCurrent() else {
                    return .canceled
                }
                let result = receive()
                if result >= 0 {
                    guard isGenerationCurrent() else {
                        return .canceled
                    }
                    didReceiveFrame()
                    frameCount += 1
                    continue
                }
                if result == AVERROR(EAGAIN) {
                    return .needsInput
                }
                if result == IR_AVERROR_EOF {
                    return .endOfStream
                }
                return .failed(result)
            }
        }

        while true {
            guard isGenerationCurrent() else {
                return .canceled(
                    frameCount: frameCount
                )
            }
            let sendResult = send()
            if sendResult >= 0 {
                break
            }
            if sendResult == IR_AVERROR_EOF {
                return .endOfStream(
                    frameCount: frameCount
                )
            }
            guard sendResult == AVERROR(EAGAIN) else {
                return .failed(
                    code: sendResult,
                    frameCount: frameCount
                )
            }

            let countBeforeReceive = frameCount
            switch receiveAvailableFrames() {
            case .needsInput:
                // FFmpeg guarantees that send and receive cannot both report
                // EAGAIN without progress. Treat a broken codec/runtime as an
                // explicit failure instead of spinning or dropping the packet.
                guard frameCount > countBeforeReceive else {
                    return .failed(
                        code: sendResult,
                        frameCount: frameCount
                    )
                }
                continue
            case .endOfStream:
                return .endOfStream(
                    frameCount: frameCount
                )
            case let .failed(code):
                return .failed(
                    code: code,
                    frameCount: frameCount
                )
            case .canceled:
                return .canceled(
                    frameCount: frameCount
                )
            }
        }

        switch receiveAvailableFrames() {
        case .needsInput:
            if input == .drain {
                // A successful NULL send enters draining mode. EAGAIN here is
                // a protocol violation; terminal state is published only
                // after AVERROR_EOF.
                return .failed(
                    code: AVERROR(EAGAIN),
                    frameCount: frameCount
                )
            }
            return .needsInput(
                frameCount: frameCount
            )
        case .endOfStream:
            return .endOfStream(
                frameCount: frameCount
            )
        case let .failed(code):
            return .failed(
                code: code,
                frameCount: frameCount
            )
        case .canceled:
            return .canceled(
                frameCount: frameCount
            )
        }
    }
}

func IRFFLog(
    context: UnsafeMutableRawPointer?,
    level: Int32,
    format: UnsafePointer<CChar>,
    args: CVaListPointer
) {
    #if IRFFFFmpegLogEnable
    guard let message = IRFFLogFormatting.message(
        format: format,
        args: args
    ) else {
        return
    }
    IRPlayerImp.Logger.libraryLogger.debug(
        IRFFLogFormatting.logLine(for: message)
    )
    #endif
}

func IRFFCheckError(_ result: Int32) -> NSError? {
    return IRFFCheckErrorCode(result, errorCode: -1)
}

func IRFFCheckErrorCode(_ result: Int32, errorCode: Int) -> NSError? {
    guard result < 0 else { return nil }

    var errorBuffer = [CChar](repeating: 0, count: 256)
    av_strerror(result, &errorBuffer, errorBuffer.count)

    let errorString = String(cString: errorBuffer)
    let errorDescription =
        "ffmpeg code: \(result), ffmpeg msg: \(errorString)"
    return NSError(
        domain: errorDescription,
        code: errorCode,
        userInfo: nil
    )
}

func IRFFFinitePositiveValueOrDefault(_ value: Double, defaultValue: Double) -> Double {
    guard value.isFinite, value > 0 else {
        return defaultValue.isFinite && defaultValue > 0
            ? defaultValue
            : 1
    }
    return value
}

func IRFFStreamGetTimebase(_ stream: UnsafePointer<AVStream>, defaultTimebase: Double) -> Double {
    let timebase: Double
    if stream.pointee.time_base.den > 0,
       stream.pointee.time_base.num > 0 {
        timebase = av_q2d(stream.pointee.time_base)
    } else {
        timebase = defaultTimebase
    }
    return IRFFFinitePositiveValueOrDefault(
        timebase,
        defaultValue: 1
    )
}

func IRFFStreamGetFPS(_ stream: UnsafePointer<AVStream>, timebase: Double) -> Double {
    let fps: Double
    if stream.pointee.avg_frame_rate.den > 0,
       stream.pointee.avg_frame_rate.num > 0 {
        fps = av_q2d(stream.pointee.avg_frame_rate)
    } else if stream.pointee.r_frame_rate.den > 0,
              stream.pointee.r_frame_rate.num > 0 {
        fps = av_q2d(stream.pointee.r_frame_rate)
    } else if timebase.isFinite, timebase > 0 {
        fps = 1 / timebase
    } else {
        fps = 1
    }
    return IRFFFinitePositiveValueOrDefault(
        fps,
        defaultValue: 1
    )
}
