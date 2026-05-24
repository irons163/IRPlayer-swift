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

enum IRPlayerNotificationPayload {

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

    static func error(_ error: IRError) -> [AnyHashable: Any] {
        return [IRPlayerErrorKey: error]
    }

    static func cgFloat(_ value: Any?) -> CGFloat {
        let converted: CGFloat
        if let value = value as? CGFloat {
            converted = value
        } else if let value = value as? NSNumber {
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
            return IRPlayerState(rawValue: value.intValue) ?? .none
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
        guard let value = value, value.doubleValue.isFinite else {
            return NSNumber(value: 0)
        }
        return value
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
        let progress = IRProgress()
        progress.percent = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerProgressPercentKey])
        progress.current = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerProgressCurrentKey])
        progress.total = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerProgressTotalKey])
        return progress
    }

    public static func playable(fromUserInfo userInfo: [AnyHashable : Any]) -> IRPlayable {
        let playable = IRPlayable()
        playable.percent = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerPlayablePercentKey])
        playable.current = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerPlayableCurrentKey])
        playable.total = IRPlayerNotificationPayload.cgFloat(userInfo[IRPlayerPlayableTotalKey])
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
