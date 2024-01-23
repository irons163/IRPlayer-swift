//
//  IRPlayerNotification.swift
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/12.
//  Copyright © 2022 Phil. All rights reserved.
//

import Foundation

@objcMembers
public class IRPlayerNotification: NSObject {

    public static func postPlayer(_ player: IRPlayerImp?, error: IRError?) {
        guard let player = player, let error = error else { return }
        let userInfo: [String: Any] = [IRPlayerErrorKey: error]
        player.error = error
        postNotification(name: IRPlayerErrorNotificationName, object: player, userInfo: userInfo)
    }

    public static func postPlayer(_ player: IRPlayerImp?, statePrevious previous: IRPlayerState, current: IRPlayerState) {
        guard let player = player else { return }
        let userInfo: [String: Any] = [IRPlayerStatePreviousKey: previous, IRPlayerStateCurrentKey: current]
        postNotification(name: IRPlayerStateChangeNotificationName, object: player, userInfo: userInfo)
    }

    public static func postPlayer(_ player: IRPlayerImp?, progressPercent percent: NSNumber?, current: NSNumber?, total: NSNumber?) {
        guard let player = player else { return }
        let percentValue = percent ?? NSNumber(value: 0)
        let currentValue = current ?? NSNumber(value: 0)
        let totalValue = total ?? NSNumber(value: 0)
        let userInfo: [String: Any] = [IRPlayerProgressPercentKey: percentValue, IRPlayerProgressCurrentKey: currentValue, IRPlayerProgressTotalKey: totalValue]
        postNotification(name: IRPlayerProgressChangeNotificationName, object: player, userInfo: userInfo)
    }

    public static func postPlayer(_ player: IRPlayerImp?, playablePercent percent: NSNumber?, current: NSNumber?, total: NSNumber?) {
        guard let player = player else { return }
        let percentValue = percent ?? NSNumber(value: 0)
        let currentValue = current ?? NSNumber(value: 0)
        let totalValue = total ?? NSNumber(value: 0)
        let userInfo: [String: Any] = [IRPlayerPlayablePercentKey: percentValue, IRPlayerPlayableCurrentKey: currentValue, IRPlayerPlayableTotalKey: totalValue]
        postNotification(name: IRPlayerPlayableChangeNotificationName, object: player, userInfo: userInfo)
    }

    public static func postNotification(name: String, object: Any?, userInfo: [String: Any]?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(name), object: object, userInfo: userInfo)
        }
    }
}
