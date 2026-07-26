//
//  IRPlayerNotificationTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

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

    func testPostPlayerStateUsesExpectedNotificationPayload() throws {
        let player = IRPlayerImp.player()
        let expectation = observeNotification(
            name: IRPlayerStateChangeNotificationName,
            object: player
        ) { notification in
            let userInfo = try XCTUnwrap(notification.userInfo)
            let state = IRModel.state(fromUserInfo: userInfo)

            XCTAssertEqual(state.previous, .buffering)
            XCTAssertEqual(state.current, .playing)
        }

        IRPlayerNotification.postPlayer(player, statePrevious: .buffering, current: .playing)

        wait(for: [expectation], timeout: 1.0)
        withExtendedLifetime(player) {}
    }

    func testQueuedPlayerNotificationIsRejectedAfterNewTransaction() {
        let player = IRPlayerImp.player()
        let expectation = expectation(
            description: "superseded notification is rejected"
        )
        expectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(
                IRPlayerStateChangeNotificationName
            ),
            object: player,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        IRPlayerNotification.postPlayer(
            player,
            statePrevious: .buffering,
            current: .playing
        )
        player.stop()

        wait(for: [expectation], timeout: 0.1)
        NotificationCenter.default.removeObserver(observer)
        withExtendedLifetime(player) {}
    }

    func testPostPlayerProgressAndPlayableUseExpectedPayloads() throws {
        let player = IRPlayerImp.player()
        let progressExpectation = observeNotification(
            name: IRPlayerProgressChangeNotificationName,
            object: player
        ) { notification in
            let userInfo = try XCTUnwrap(notification.userInfo)
            let progress = IRModel.progress(fromUserInfo: userInfo)

            XCTAssertEqual(progress.percent, 0.25)
            XCTAssertEqual(progress.current, 3)
            XCTAssertEqual(progress.total, 12)
        }
        let playableExpectation = observeNotification(
            name: IRPlayerPlayableChangeNotificationName,
            object: player
        ) { notification in
            let userInfo = try XCTUnwrap(notification.userInfo)
            let playable = IRModel.playable(fromUserInfo: userInfo)

            XCTAssertEqual(playable.percent, 0.5)
            XCTAssertEqual(playable.current, 6)
            XCTAssertEqual(playable.total, 12)
        }

        IRPlayerNotification.postPlayer(
            player,
            progressPercent: NSNumber(value: 0.25),
            current: NSNumber(value: 3),
            total: NSNumber(value: 12)
        )
        IRPlayerNotification.postPlayer(
            player,
            playablePercent: NSNumber(value: 0.5),
            current: NSNumber(value: 6),
            total: NSNumber(value: 12)
        )

        wait(for: [progressExpectation, playableExpectation], timeout: 1.0)
        withExtendedLifetime(player) {}
    }

    func testPostPlayerErrorStoresErrorAndPostsPayload() throws {
        let player = IRPlayerImp.player()
        let error = IRError()
        error.error = NSError(domain: "IRPlayerNotificationTests", code: 42)
        let expectation = observeNotification(
            name: IRPlayerErrorNotificationName,
            object: player
        ) { notification in
            let userInfo = try XCTUnwrap(notification.userInfo)
            XCTAssertTrue(IRModel.error(fromUserInfo: userInfo) === error)
        }

        IRPlayerNotification.postPlayer(player, error: error)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(player.error === error)
        withExtendedLifetime(player) {}
    }

    func testBackgroundErrorPostsTypedThenLegacyOnMain() {
        let player = IRPlayerImp.player()
        let error = IRError()
        error.error = NSError(
            domain: "IRPlayerNotificationTests.background",
            code: 43
        )
        var deliveryOrder: [String] = []
        let typed = expectation(
            description: "typed event delivered on main"
        )
        let legacy = expectation(
            description: "legacy event delivered on main"
        )
        let observation = player.observeEvents { event in
            guard case let .failure(receivedError) = event else {
                return
            }
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(receivedError === error)
            XCTAssertTrue(player.error === error)
            deliveryOrder.append("typed")
            typed.fulfill()
        }
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(
                IRPlayerErrorNotificationName
            ),
            object: player,
            queue: .main
        ) { _ in
            XCTAssertTrue(Thread.isMainThread)
            deliveryOrder.append("legacy")
            legacy.fulfill()
        }

        DispatchQueue.global().async {
            IRPlayerNotification.postPlayer(
                player,
                error: error
            )
        }

        wait(for: [typed, legacy], timeout: 1)
        XCTAssertEqual(deliveryOrder, ["typed", "legacy"])
        NotificationCenter.default.removeObserver(observer)
        withExtendedLifetime(observation) {}
        withExtendedLifetime(player) {}
    }

    func testSupersededBackgroundPostIsRejectedBeforeTypedDelivery() {
        let player = IRPlayerImp.player()
        let error = IRError()
        let enqueued = DispatchSemaphore(value: 0)
        let typed = expectation(
            description: "superseded typed event rejected"
        )
        typed.isInverted = true
        let legacy = expectation(
            description: "superseded legacy event rejected"
        )
        legacy.isInverted = true
        let observation = player.observeEvents { event in
            guard case .failure = event else { return }
            typed.fulfill()
        }
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(
                IRPlayerErrorNotificationName
            ),
            object: player,
            queue: .main
        ) { _ in
            legacy.fulfill()
        }

        DispatchQueue.global().async {
            IRPlayerNotification.postPlayer(
                player,
                error: error
            )
            enqueued.signal()
        }
        XCTAssertEqual(
            enqueued.wait(timeout: .now() + 1),
            .success
        )
        player.stop()

        wait(for: [typed, legacy], timeout: 0.1)
        XCTAssertNil(player.error)
        NotificationCenter.default.removeObserver(observer)
        withExtendedLifetime(observation) {}
        withExtendedLifetime(player) {}
    }

    func testPostPlayerErrorIgnoresMissingError() {
        let player = IRPlayerImp.player()
        let expectation = expectation(description: "missing error does not post")
        expectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(IRPlayerErrorNotificationName),
            object: player,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        IRPlayerNotification.postPlayer(player, error: nil)

        wait(for: [expectation], timeout: 0.1)
        NotificationCenter.default.removeObserver(observer)
        withExtendedLifetime(player) {}
    }

    private func observeNotification(
        name: String,
        object: Any?,
        verify: @escaping (Notification) throws -> Void
    ) -> XCTestExpectation {
        let expectation = expectation(description: "\(name) posted")
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(name),
            object: object,
            queue: .main
        ) { notification in
            do {
                try verify(notification)
            } catch {
                XCTFail("Notification verification failed: \(error)")
            }
            expectation.fulfill()
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(observer)
        }
        return expectation
    }
}
