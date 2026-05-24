//
//  IRPlayerNotificationTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
@testable import IRPlayer_swift

final class IRPlayerNotificationTests: XCTestCase {

    func testPostNotificationPostsAsynchronouslyOnMainQueue() {
        let name = Notification.Name("IRPlayerNotificationTests.\(UUID().uuidString)")
        let expectation = expectation(description: "notification posted")
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(notification.userInfo?[IRPlayerProgressCurrentKey] as? NSNumber, NSNumber(value: 2))
            expectation.fulfill()
        }

        IRPlayerNotification.postNotification(name: name.rawValue, object: nil, userInfo: [
            IRPlayerProgressCurrentKey: NSNumber(value: 2)
        ])

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
