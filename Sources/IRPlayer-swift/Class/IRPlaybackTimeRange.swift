import Foundation

enum IRPlaybackTimeValue {
    static let maximumSeconds =
        Double(Int64.max) / 1_000_000_000

    static func normalized(
        _ value: TimeInterval
    ) -> TimeInterval? {
        guard value.isFinite,
              value >= 0,
              value <= maximumSeconds else {
            return nil
        }
        return value
    }

    static func normalizedOrZero(
        _ value: TimeInterval
    ) -> TimeInterval {
        normalized(value) ?? 0
    }
}

struct IRPlaybackTimeRange: Equatable, Sendable {
    let duration: TimeInterval

    init?(duration: TimeInterval) {
        guard duration.isFinite, duration >= 0 else {
            return nil
        }
        self.duration = duration
    }

    func clamped(_ time: TimeInterval) -> TimeInterval? {
        guard time.isFinite else { return nil }
        return min(max(time, 0), duration)
    }
}
