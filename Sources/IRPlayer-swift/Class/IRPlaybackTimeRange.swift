import Foundation

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
