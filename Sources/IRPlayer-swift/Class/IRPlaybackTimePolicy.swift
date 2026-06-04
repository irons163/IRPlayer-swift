import Foundation

enum IRPlaybackTimePolicy {
    struct ProgressPostDecision: Equatable {
        let shouldPost: Bool
        let current: TimeInterval
        let total: TimeInterval
        let nextLastPostTime: TimeInterval
    }

    static func percent(current: TimeInterval, total: TimeInterval) -> NSNumber {
        guard current.isFinite, total.isFinite, total > 0 else {
            return NSNumber(value: 0)
        }
        let boundedCurrent = min(max(current, 0), total)
        let percent = boundedCurrent / total
        return NSNumber(value: percent.isFinite ? percent : 0)
    }

    static func clampedPlayableTime(_ playableTime: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard playableTime.isFinite, duration.isFinite, duration >= 0 else { return 0 }
        return min(max(playableTime, 0), duration)
    }

    static func clampedSeekTime(requested: TimeInterval, min minTime: TimeInterval, max maxTime: TimeInterval) -> TimeInterval? {
        guard requested.isFinite, minTime.isFinite, maxTime.isFinite else { return nil }
        let resolvedMaxTime = maxTime < minTime ? minTime : maxTime
        if requested > resolvedMaxTime {
            return resolvedMaxTime
        }
        if requested < minTime {
            return minTime
        }
        return requested
    }

    static func bufferingState(
        currentlyBuffering: Bool,
        bufferedDuration: TimeInterval,
        minBufferedDuration: TimeInterval,
        endOfFile: Bool
    ) -> Bool {
        let safeBufferedDuration = bufferedDuration.isFinite ? bufferedDuration : 0
        let safeMinBufferedDuration = minBufferedDuration.isFinite ? minBufferedDuration : 0
        if currentlyBuffering {
            return !(safeBufferedDuration >= safeMinBufferedDuration || endOfFile)
        }
        return safeBufferedDuration <= 0.2 && !endOfFile
    }

    static func progressPostDecision(
        progress: TimeInterval,
        oldProgress: TimeInterval,
        duration: TimeInterval,
        lastPostTime: TimeInterval,
        now: TimeInterval,
        seekEnabled: Bool
    ) -> ProgressPostDecision {
        let safeDuration = duration.isFinite ? duration : 0
        guard progress != oldProgress else {
            return ProgressPostDecision(shouldPost: false, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }
        guard progress.isFinite else {
            return ProgressPostDecision(shouldPost: false, current: 0, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        if progress <= 0.000001 || progress == safeDuration {
            return ProgressPostDecision(shouldPost: true, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        guard now.isFinite, lastPostTime.isFinite, now - lastPostTime >= 1 else {
            return ProgressPostDecision(shouldPost: false, current: progress, total: safeDuration, nextLastPostTime: lastPostTime)
        }

        let effectiveDuration = seekEnabled ? safeDuration : progress
        return ProgressPostDecision(shouldPost: true, current: progress, total: effectiveDuration, nextLastPostTime: now)
    }
}
