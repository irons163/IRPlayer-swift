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
        let generation =
            player.backendCoordinator.currentTransactionGeneration
        IRMainThreadExecutor.execute {
            guard player.backendCoordinator.isCurrentTransaction(
                generation
            ) else {
                return
            }
            let userInfo = IRPlayerNotificationPayload.error(error)
            player.error = error
            player.emit(.failure(error))
            postPlayerNotification(
                name: IRPlayerErrorNotificationName,
                player: player,
                userInfo: userInfo,
                generation: generation
            )
        }
    }

    public static func postPlayer(_ player: IRPlayerImp?, statePrevious previous: IRPlayerState, current: IRPlayerState) {
        guard let player = player else { return }
        let generation =
            player.backendCoordinator.currentTransactionGeneration
        IRMainThreadExecutor.execute {
            guard player.backendCoordinator.isCurrentTransaction(
                generation
            ) else {
                return
            }
            let userInfo = IRPlayerNotificationPayload.state(
                previous: previous,
                current: current
            )
            player.emit(
                .stateChanged(
                    previous: previous,
                    current: current
                )
            )
            postPlayerNotification(
                name: IRPlayerStateChangeNotificationName,
                player: player,
                userInfo: userInfo,
                generation: generation
            )
        }
    }

    public static func postPlayer(_ player: IRPlayerImp?, progressPercent percent: NSNumber?, current: NSNumber?, total: NSNumber?) {
        guard let player = player else { return }
        let generation =
            player.backendCoordinator.currentTransactionGeneration
        IRMainThreadExecutor.execute {
            guard player.backendCoordinator.isCurrentTransaction(
                generation
            ) else {
                return
            }
            let values = IRPlayerNotificationPayload.timeValues(
                percent: percent,
                current: current,
                total: total
            )
            let userInfo =
                IRPlayerNotificationPayload.progress(values)
            player.emit(.progress(values.snapshot))
            postPlayerNotification(
                name: IRPlayerProgressChangeNotificationName,
                player: player,
                userInfo: userInfo,
                generation: generation
            )
        }
    }

    public static func postPlayer(_ player: IRPlayerImp?, playablePercent percent: NSNumber?, current: NSNumber?, total: NSNumber?) {
        guard let player = player else { return }
        let generation =
            player.backendCoordinator.currentTransactionGeneration
        IRMainThreadExecutor.execute {
            guard player.backendCoordinator.isCurrentTransaction(
                generation
            ) else {
                return
            }
            let values = IRPlayerNotificationPayload.timeValues(
                percent: percent,
                current: current,
                total: total
            )
            let userInfo =
                IRPlayerNotificationPayload.playable(values)
            player.emit(.playable(values.snapshot))
            postPlayerNotification(
                name: IRPlayerPlayableChangeNotificationName,
                player: player,
                userInfo: userInfo,
                generation: generation
            )
        }
    }

    public static func postNotification(name: String, object: Any?, userInfo: [AnyHashable: Any]?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(name), object: object, userInfo: userInfo)
        }
    }

    private static func postPlayerNotification(
        name: String,
        player: IRPlayerImp,
        userInfo: [AnyHashable: Any],
        generation: UInt64
    ) {
        DispatchQueue.main.async {
            guard player.backendCoordinator.isCurrentTransaction(
                generation
            ) else {
                return
            }
            NotificationCenter.default.post(
                name: Notification.Name(name),
                object: player,
                userInfo: userInfo
            )
        }
    }

}
