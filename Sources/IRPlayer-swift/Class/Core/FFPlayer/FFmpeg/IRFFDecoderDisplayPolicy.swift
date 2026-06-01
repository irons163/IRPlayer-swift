import Foundation

enum IRFFDecoderDisplayPolicy {

    static func audioSyncedVideoSleepDuration(framePosition: TimeInterval,
                                              frameDuration: TimeInterval,
                                              audioTimeClock: TimeInterval,
                                              fps: TimeInterval) -> TimeInterval? {
        let sleepTime: TimeInterval
        if framePosition >= audioTimeClock {
            guard let frameInterval = frameInterval(forFPS: fps) else { return nil }
            sleepTime = frameInterval / 2
        } else if framePosition + frameDuration >= audioTimeClock {
            guard frameDuration.isFinite, frameDuration > 0 else { return nil }
            sleepTime = frameDuration / 2
        } else {
            return nil
        }

        return sleepTime < 0.015 ? 0.015 : sleepTime
    }

    static func standaloneVideoSleepDuration(frameDuration: TimeInterval, fps: TimeInterval) -> TimeInterval? {
        if frameDuration.isFinite, frameDuration >= 0.0001 {
            return frameDuration
        }
        return frameInterval(forFPS: fps)
    }

    static func videoFrameOrderingPosition(_ position: TimeInterval?) -> TimeInterval? {
        guard let position else { return 0 }
        return position.isFinite ? position : nil
    }

    static func shouldAcceptVideoFrame(currentPosition: TimeInterval?, nextPosition: TimeInterval?) -> Bool {
        guard let nextPosition = videoFrameOrderingPosition(nextPosition) else { return false }
        guard let currentPosition = videoFrameOrderingPosition(currentPosition) else { return true }
        return currentPosition <= nextPosition
    }

    static func displayIdleSleepInterval(seeking: Bool,
                                         buffering: Bool,
                                         paused: Bool,
                                         hasCurrentFrame: Bool) -> TimeInterval? {
        if seeking || buffering {
            return 0.01
        }
        if paused, hasCurrentFrame {
            return 0.03
        }
        return nil
    }

    static func shouldFinishDisplay(endOfFile: Bool, videoDecoderEmpty: Bool) -> Bool {
        return endOfFile && videoDecoderEmpty
    }

    private static func frameInterval(forFPS fps: TimeInterval) -> TimeInterval? {
        guard fps.isFinite, fps > 0 else { return nil }
        let interval = 1.0 / fps
        guard interval.isFinite, interval > 0 else { return nil }
        return interval
    }
}
