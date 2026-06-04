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
