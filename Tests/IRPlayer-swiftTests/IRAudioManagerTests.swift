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
}

final class IRAudioManagerRenderTests: XCTestCase {

    func testRequiredAudioGraphRejectsMissingGraph() {
        let result = IRAudioManager.requiredAudioGraph(nil, domain: "missing graph")

        switch result {
        case .success:
            XCTFail("Missing graph should not be accepted")
        case .failure(let error):
            XCTAssertEqual(error.domain, "missing graph")
            XCTAssertEqual(error.code, -1)
        }
    }

    func testRequiredAudioUnitRejectsMissingUnit() {
        let result = IRAudioManager.requiredAudioUnit(nil, domain: "missing audio unit")

        switch result {
        case .success:
            XCTFail("Missing audio unit should not be accepted")
        case .failure(let error):
            XCTAssertEqual(error.domain, "missing audio unit")
            XCTAssertEqual(error.code, -1)
        }
    }

    func testRenderFramesIgnoresMissingAudioBufferList() {
        let manager = IRAudioManager()

        XCTAssertEqual(manager.renderFrames(16, ioData: nil), noErr)
    }

    func testRenderSampleCountRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: 0, numberOfChannels: 2))
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: 10, numberOfChannels: 0))
        XCTAssertNil(IRAudioManager.renderSampleCount(numberOfFrames: .max, numberOfChannels: .max))
    }

    func testRenderSampleCountCalculatesInterleavedSampleTotal() {
        XCTAssertEqual(IRAudioManager.renderSampleCount(numberOfFrames: 10, numberOfChannels: 2), 20)
    }
}
