import AVFoundation

enum IRAVPlayerTimePolicy {

    static func seekTime(for time: TimeInterval) -> CMTime? {
        guard time.isFinite, time >= 0 else { return nil }
        let seekTime = CMTimeMakeWithSeconds(time, preferredTimescale: Int32(NSEC_PER_SEC))
        guard seekTime.isValid else { return nil }
        return seekTime
    }

    static func finiteSeconds(from time: CMTime) -> TimeInterval {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return 0 }
        return seconds
    }

    static func playableEndTime(start: TimeInterval, duration: TimeInterval, totalDuration: TimeInterval) -> TimeInterval {
        let end = start + duration
        guard start.isFinite, duration.isFinite, end.isFinite else { return 0 }
        return IRPlaybackTimePolicy.clampedPlayableTime(end, duration: totalDuration)
    }
}
