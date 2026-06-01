import Foundation
import IRFFMpeg
import IRPlayerObjc

enum IRFFVideoDecoderPolicy {
    private static let maxVideoFrameSleepFullTimeInterval: TimeInterval = 0.1
    private static let maxVideoFrameSleepFullAndPauseTimeInterval: TimeInterval = 0.5

    static func frameDuration(ticks: Int64,
                              repeatPicture: Int32,
                              timebase: TimeInterval,
                              fps: TimeInterval) -> TimeInterval {
        if ticks != 0 {
            guard timebase.isFinite, timebase > 0 else { return 0 }
            let baseDuration = TimeInterval(ticks) * timebase
            let repeatDuration = TimeInterval(repeatPicture) * timebase * 0.5
            let duration = baseDuration + repeatDuration
            return duration.isFinite && duration > 0 ? duration : 0
        }

        guard fps.isFinite, fps > 0 else { return 0 }
        let duration = 1.0 / fps
        return duration.isFinite && duration > 0 ? duration : 0
    }

    static func decodeBackpressureSleepInterval(frameDuration: TimeInterval,
                                                maxDecodeDuration: TimeInterval,
                                                paused: Bool) -> TimeInterval? {
        guard frameDuration.isFinite,
              maxDecodeDuration.isFinite,
              maxDecodeDuration > 0 else {
            return nil
        }
        guard frameDuration >= maxDecodeDuration else { return nil }
        return paused ? maxVideoFrameSleepFullAndPauseTimeInterval : maxVideoFrameSleepFullTimeInterval
    }

    static func packetDecodeResultIsFailure(_ result: Int32) -> Bool {
        guard result < 0 else { return false }
        return result != AVERROR(EAGAIN) && result != IR_AVERROR_EOF
    }

    static func shouldFinishDecode(endOfFile: Bool, packetEmpty: Bool) -> Bool {
        return endOfFile && packetEmpty
    }

    static func decodeIdleSleepInterval(paused: Bool) -> TimeInterval? {
        return paused ? 0.01 : nil
    }

    static func shouldCreateYUVFrame(hasFrame: Bool,
                                     hasLuma: Bool,
                                     hasChromaB: Bool,
                                     hasChromaR: Bool) -> Bool {
        return hasFrame && hasLuma && hasChromaB && hasChromaR
    }
}
