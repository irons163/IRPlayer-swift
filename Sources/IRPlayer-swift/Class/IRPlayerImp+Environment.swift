import Foundation
import UIKit

extension IRPlayerImp {
    func applicationDidEnterBackground(_ notification: NSNotification) {
        environmentSession.didEnterBackground()
    }

    func applicationWillEnterForeground(_ notification: NSNotification) {
        environmentSession.willEnterForeground()
    }
}

public extension IRPlayerImp {
    func registerPlayerNotification(
        target: Any?,
        stateAction: Selector? = nil,
        progressAction: Selector? = nil,
        playableAction: Selector? = nil,
        errorAction: Selector? = nil
    ) {
        guard let target else { return }
        removePlayerNotification(target: target)
        let center = NotificationCenter.default

        if let stateAction {
            center.addObserver(
                target,
                selector: stateAction,
                name: Notification.Name(IRPlayerStateChangeNotificationName),
                object: self
            )
        }
        if let progressAction {
            center.addObserver(
                target,
                selector: progressAction,
                name: Notification.Name(
                    IRPlayerProgressChangeNotificationName
                ),
                object: self
            )
        }
        if let playableAction {
            center.addObserver(
                target,
                selector: playableAction,
                name: Notification.Name(
                    IRPlayerPlayableChangeNotificationName
                ),
                object: self
            )
        }
        if let errorAction {
            center.addObserver(
                target,
                selector: errorAction,
                name: Notification.Name(IRPlayerErrorNotificationName),
                object: self
            )
        }
    }

    func removePlayerNotification(target: Any) {
        let center = NotificationCenter.default
        center.removeObserver(
            target,
            name: Notification.Name(IRPlayerStateChangeNotificationName),
            object: self
        )
        center.removeObserver(
            target,
            name: Notification.Name(IRPlayerProgressChangeNotificationName),
            object: self
        )
        center.removeObserver(
            target,
            name: Notification.Name(IRPlayerPlayableChangeNotificationName),
            object: self
        )
        center.removeObserver(
            target,
            name: Notification.Name(IRPlayerErrorNotificationName),
            object: self
        )
    }
}
