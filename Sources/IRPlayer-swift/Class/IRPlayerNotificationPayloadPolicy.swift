import UIKit

enum IRPlayerNotificationPayloadPolicy {

    static func state(previous: IRPlayerState, current: IRPlayerState) -> [AnyHashable: Any] {
        return [
            IRPlayerStatePreviousKey: previous,
            IRPlayerStateCurrentKey: current
        ]
    }

    static func progress(percent: NSNumber?, current: NSNumber?, total: NSNumber?) -> [AnyHashable: Any] {
        return timePayload(percent: percent, current: current, total: total)
    }

    static func playable(percent: NSNumber?, current: NSNumber?, total: NSNumber?) -> [AnyHashable: Any] {
        return timePayload(percent: percent, current: current, total: total)
    }

    static func timePercent(current: TimeInterval, total: TimeInterval) -> NSNumber {
        return IRPlaybackTimePolicy.percent(current: current, total: total)
    }

    static func error(_ error: IRError) -> [AnyHashable: Any] {
        return [IRPlayerErrorKey: error]
    }

    static func cgFloat(_ value: Any?) -> CGFloat {
        if value is Bool {
            return 0
        }

        let converted: CGFloat
        if let value = value as? CGFloat {
            converted = value
        } else if let value = value as? NSNumber {
            guard !IRPayloadNumber.isBoolean(value) else { return 0 }
            converted = CGFloat(truncating: value)
        } else if let value = value as? Double {
            converted = CGFloat(value)
        } else if let value = value as? Float {
            converted = CGFloat(value)
        } else if let value = value as? Int {
            converted = CGFloat(value)
        } else {
            return 0
        }
        return converted.isFinite ? converted : 0
    }

    static func state(_ value: Any?) -> IRPlayerState {
        if let value = value as? IRPlayerState {
            return value
        }
        if let value = value as? NSNumber {
            guard let rawValue = IRPayloadNumber.integerRawValue(from: value) else { return .none }
            return IRPlayerState(rawValue: rawValue) ?? .none
        }
        if let value = value as? Int {
            return IRPlayerState(rawValue: value) ?? .none
        }
        return .none
    }

    private static func timePayload(percent: NSNumber?, current: NSNumber?, total: NSNumber?) -> [AnyHashable: Any] {
        return [
            IRPlayerProgressPercentKey: finiteNumber(percent),
            IRPlayerProgressCurrentKey: finiteNumber(current),
            IRPlayerProgressTotalKey: finiteNumber(total)
        ]
    }

    private static func finiteNumber(_ value: NSNumber?) -> NSNumber {
        guard let value = value,
              !IRPayloadNumber.isBoolean(value),
              value.doubleValue.isFinite else {
            return NSNumber(value: 0)
        }
        return value
    }
}
