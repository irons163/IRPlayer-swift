//
//  IRPlayerAction.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/1/22.
//

import UIKit

// MARK: - Extern and Notifications
#if canImport(Darwin)
public let IRPlayerErrorNotificationName: String = "IRPlayerErrorNotificationName" // player error
public let IRPlayerStateChangeNotificationName: String = "IRPlayerStateChangeNotificationName" // player state change
public let IRPlayerProgressChangeNotificationName: String = "IRPlayerProgressChangeNotificationName" // player play progress change
public let IRPlayerPlayableChangeNotificationName: String = "IRPlayerPlayableChangeNotificationName" // player playable progress change
#endif

// MARK: - Notification Userinfo Keys
public let IRPlayerErrorKey: String = "error" // error
public let IRPlayerStatePreviousKey: String = "previous" // state
public let IRPlayerStateCurrentKey: String = "current" // state
public let IRPlayerProgressPercentKey: String = "percent" // progress
public let IRPlayerProgressCurrentKey: String = "current" // progress
public let IRPlayerProgressTotalKey: String = "total" // progress
public let IRPlayerPlayablePercentKey: String = "percent" // playable
public let IRPlayerPlayableCurrentKey: String = "current" // playable
public let IRPlayerPlayableTotalKey: String = "total" // playable

enum IRPayloadNumber {

    static func isBoolean(_ value: NSNumber) -> Bool {
        return CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    static func isInteger(_ value: NSNumber) -> Bool {
        guard !isBoolean(value) else {
            return false
        }

        switch String(cString: value.objCType) {
        case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
            return true
        default:
            return false
        }
    }

    static func integerRawValue(from value: NSNumber) -> Int? {
        guard isInteger(value) else {
            return nil
        }
        let decimalValue = value.decimalValue
        guard decimalValue >= NSNumber(value: Int.min).decimalValue,
              decimalValue <= NSNumber(value: Int.max).decimalValue else {
            return nil
        }
        return value.intValue
    }
}

enum IRPlayerNotificationPayload {
    struct TimeValues: Equatable {
        let fraction: Double
        let current: TimeInterval
        let total: TimeInterval

        var snapshot: IRPlayerTimeSnapshot {
            IRPlayerTimeSnapshot(
                current: current,
                total: total,
                fraction: fraction
            )
        }
    }

    static func state(previous: IRPlayerState, current: IRPlayerState) -> [AnyHashable: Any] {
        return [
            IRPlayerStatePreviousKey: previous,
            IRPlayerStateCurrentKey: current
        ]
    }

    static func progress(percent: NSNumber?, current: NSNumber?, total: NSNumber?) -> [AnyHashable: Any] {
        progress(
            timeValues(
                percent: percent,
                current: current,
                total: total
            )
        )
    }

    static func progress(
        _ values: TimeValues
    ) -> [AnyHashable: Any] {
        return [
            IRPlayerProgressPercentKey:
                NSNumber(value: values.fraction),
            IRPlayerProgressCurrentKey:
                NSNumber(value: values.current),
            IRPlayerProgressTotalKey:
                NSNumber(value: values.total)
        ]
    }

    static func playable(percent: NSNumber?, current: NSNumber?, total: NSNumber?) -> [AnyHashable: Any] {
        playable(
            timeValues(
                percent: percent,
                current: current,
                total: total
            )
        )
    }

    static func playable(
        _ values: TimeValues
    ) -> [AnyHashable: Any] {
        return [
            IRPlayerPlayablePercentKey:
                NSNumber(value: values.fraction),
            IRPlayerPlayableCurrentKey:
                NSNumber(value: values.current),
            IRPlayerPlayableTotalKey:
                NSNumber(value: values.total)
        ]
    }

    static func timeValues(
        percent: Any?,
        current: Any?,
        total: Any?
    ) -> TimeValues {
        TimeValues(
            fraction: sanitizedFraction(percent),
            current: sanitizedTime(current),
            total: sanitizedTime(total)
        )
    }

    static func timePercent(current: TimeInterval, total: TimeInterval) -> NSNumber {
        let sanitizedTotal = sanitizedTime(total)
        let sanitizedCurrent = sanitizedTime(current)
        guard sanitizedTotal > 0,
              let range = IRPlaybackTimeRange(
                  duration: sanitizedTotal
              ),
              let boundedCurrent =
                range.clamped(sanitizedCurrent) else {
            return NSNumber(value: 0)
        }
        let percent = boundedCurrent / range.duration
        return NSNumber(value: percent.isFinite ? percent : 0)
    }

    static func error(_ error: IRError) -> [AnyHashable: Any] {
        return [IRPlayerErrorKey: error]
    }

    static func cgFloat(_ value: Any?) -> CGFloat {
        let converted: CGFloat
        if let value = value as? NSNumber {
            guard !IRPayloadNumber.isBoolean(value) else {
                return 0
            }
            converted = CGFloat(truncating: value)
        } else if value is Bool {
            return 0
        } else if let value = value as? CGFloat {
            converted = value
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
            guard let rawValue =
                IRPayloadNumber.integerRawValue(from: value) else {
                return .none
            }
            return IRPlayerState(rawValue: rawValue) ?? .none
        }
        if let value = value as? Int {
            return IRPlayerState(rawValue: value) ?? .none
        }
        return .none
    }

    private static func sanitizedFraction(_ value: Any?) -> Double {
        guard let converted = numericDouble(value),
              let normalized =
                IRPlaybackTimeValue.normalized(converted) else {
            return 0
        }
        return min(normalized, 1)
    }

    private static func sanitizedTime(_ value: Any?) -> TimeInterval {
        guard let converted = numericDouble(value),
              let normalized =
                IRPlaybackTimeValue.normalized(converted) else {
            return 0
        }
        return normalized
    }

    private static func numericDouble(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard !IRPayloadNumber.isBoolean(value) else {
                return nil
            }
            return value.doubleValue
        }
        if value is Bool {
            return nil
        }
        if let value = value as? CGFloat {
            return Double(value)
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Float {
            return Double(value)
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }
}

// MARK: - Player State Enum
//@objc public enum IRPlayerState: Int {
//    case none = 0          // none
//    case buffering = 1     // buffering
//    case readyToPlay = 2   // ready to play
//    case playing = 3       // playing
//    case suspend = 4       // pause
//    case finished = 5      // finished
//    case failed = 6        // failed
//}

// MARK: - IRPlayer Action Models

public class IRModel: NSObject {

    public static func state(fromUserInfo userInfo: [AnyHashable : Any]) -> IRState {
        let state = IRState()
        state.previous = IRPlayerNotificationPayload.state(userInfo[IRPlayerStatePreviousKey])
        state.current = IRPlayerNotificationPayload.state(userInfo[IRPlayerStateCurrentKey])
        return state
    }

    public static func progress(fromUserInfo userInfo: [AnyHashable : Any]) -> IRProgress {
        let values = IRPlayerNotificationPayload.timeValues(
            percent: userInfo[IRPlayerProgressPercentKey],
            current: userInfo[IRPlayerProgressCurrentKey],
            total: userInfo[IRPlayerProgressTotalKey]
        )
        let progress = IRProgress()
        progress.percent = CGFloat(values.fraction)
        progress.current = CGFloat(values.current)
        progress.total = CGFloat(values.total)
        return progress
    }

    public static func playable(fromUserInfo userInfo: [AnyHashable : Any]) -> IRPlayable {
        let values = IRPlayerNotificationPayload.timeValues(
            percent: userInfo[IRPlayerPlayablePercentKey],
            current: userInfo[IRPlayerPlayableCurrentKey],
            total: userInfo[IRPlayerPlayableTotalKey]
        )
        let playable = IRPlayable()
        playable.percent = CGFloat(values.fraction)
        playable.current = CGFloat(values.current)
        playable.total = CGFloat(values.total)
        return playable
    }

    public static func error(fromUserInfo userInfo: [AnyHashable : Any]) -> IRError {
        if let error = userInfo[IRPlayerErrorKey] as? IRError {
            return error
        } else if let error = userInfo[IRPlayerErrorKey] as? NSError {
            let obj = IRError()
            obj.error = error
            return obj
        } else {
            let obj = IRError()
            obj.error = IRError.makeDefaultNSError()
            return obj
        }
    }
}

@objcMembers
public class IRState: IRModel {
    public var previous: IRPlayerState = .none
    public var current: IRPlayerState = .none
}

public class IRProgress: IRModel {
    public var percent: CGFloat = 0.0
    public var current: CGFloat = 0.0
    public var total: CGFloat = 0.0
}

public class IRPlayable: IRModel {
    public var percent: CGFloat = 0.0
    public var current: CGFloat = 0.0
    public var total: CGFloat = 0.0
}

@objcMembers
public class IRErrorEvent: IRModel {
    public var date: Date?
    public var URI: String?
    public var serverAddress: String?
    public var playbackSessionID: String?
    public var errorStatusCode: Int = 0
    public var errorDomain: String = ""
    public var errorComment: String?
}

@objcMembers
public class IRError: IRModel {
    public var error: NSError = IRError.makeDefaultNSError()
    public var extendedLogData: Data?
    public var extendedLogDataStringEncoding: UInt = String.Encoding.utf8.rawValue
    public var errorEvents: [IRErrorEvent]?

    static func makeDefaultNSError() -> NSError {
        return NSError(domain: "IRPlayer error", code: -1, userInfo: nil)
    }
}
