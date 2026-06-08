//
//  IRAudioManagerTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import AVFoundation
import XCTest
@testable import IRPlayer_swift

final class IRAudioManagerNotificationTests: XCTestCase {

    func testAudioSessionInterruptionNotificationCallsHandlerWithMappedTypeAndOption() {
        let manager = IRAudioManager()
        let target = NSObject()
        var received: [(type: IRAudioManagerInterruptionType, option: IRAudioManagerInterruptionOption)] = []
        manager.setHandlerTarget(target, interruption: { handlerTarget, _, type, option in
            XCTAssertTrue(handlerTarget === target)
            received.append((type, option))
        }, routeChange: { _, _, _ in
            XCTFail("Route change handler should not be called for interruption notifications")
        })

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )

        XCTAssertEqual(received.map(\.type), [.begin, .ended])
        XCTAssertEqual(received.map(\.option), [.none, .shouldResume])
    }

    func testAudioSessionRouteChangeNotificationCallsHandlerForOldDeviceUnavailable() {
        let manager = IRAudioManager()
        let target = NSObject()
        var receivedReasons: [IRAudioManagerRouteChangeReason] = []
        manager.setHandlerTarget(target, interruption: { _, _, _, _ in
            XCTFail("Interruption handler should not be called for route change notifications")
        }, routeChange: { handlerTarget, _, reason in
            XCTAssertTrue(handlerTarget === target)
            receivedReasons.append(reason)
        })

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            ]
        )

        XCTAssertEqual(receivedReasons, [.oldDeviceUnavailable])
    }

    func testRemoveHandlerTargetClearsMatchingOrMissingTarget() {
        let manager = IRAudioManager()
        let target = NSObject()
        var interruptionCallCount = 0
        manager.setHandlerTarget(target, interruption: { _, _, _, _ in
            interruptionCallCount += 1
        }, routeChange: { _, _, _ in })

        manager.removeHandlerTarget(NSObject())
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        manager.removeHandlerTarget(target)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        manager.removeHandlerTarget(target)

        XCTAssertEqual(interruptionCallCount, 1)
    }

    func testMalformedAudioSessionNotificationsAreIgnored() {
        let manager = IRAudioManager()
        let target = NSObject()
        var interruptionCalled = false
        var routeChangeCalled = false
        manager.setHandlerTarget(target, interruption: { _, _, _, _ in
            interruptionCalled = true
        }, routeChange: { _, _, _ in
            routeChangeCalled = true
        })

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [:])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [:])

        XCTAssertFalse(interruptionCalled)
        XCTAssertFalse(routeChangeCalled)
    }

    func testUnsignedIntegerRejectsNegativeNumericPayloads() {
        XCTAssertNil(IRAudioManager.unsignedInteger(from: -1))
        XCTAssertNil(IRAudioManager.unsignedInteger(from: NSNumber(value: -1)))
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: UInt(3)), 3)
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: NSNumber(value: 4)), 4)
    }

    func testUnsignedIntegerRejectsFractionalAndBooleanNumericPayloads() {
        XCTAssertNil(IRAudioManager.unsignedInteger(from: NSNumber(value: 1.5)))
        XCTAssertNil(IRAudioManager.unsignedInteger(from: NSNumber(value: true)))
    }

    func testUnsignedIntegerWrapperMatchesPolicy() {
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: UInt(3)), IRAudioManagerPolicy.unsignedInteger(from: UInt(3)))
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: NSNumber(value: 4)), IRAudioManagerPolicy.unsignedInteger(from: NSNumber(value: 4)))
        XCTAssertNil(IRAudioManagerPolicy.unsignedInteger(from: NSNumber(value: -1)))
        XCTAssertNil(IRAudioManagerPolicy.unsignedInteger(from: NSNumber(value: true)))
    }
}
