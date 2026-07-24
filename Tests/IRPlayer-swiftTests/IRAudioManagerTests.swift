import AVFoundation
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRAudioManagerNotificationTests: XCTestCase {
    func testInterruptionNotificationsDeliverMappedEventsToCurrentTarget() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        let target = NSObject()
        var received: [(
            IRAudioManagerInterruptionType,
            IRAudioManagerInterruptionOption
        )] = []
        manager.setHandlerTarget(
            target,
            interruption: { handlerTarget, _, type, option in
                XCTAssertTrue(handlerTarget === target)
                received.append((type, option))
            },
            routeChange: { _, _, _ in
                XCTFail("Unexpected route-change delivery")
            }
        )

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey:
                    AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )

        XCTAssertEqual(received.map(\.0), [.begin, .ended])
        XCTAssertEqual(received.map(\.1), [.none, .shouldResume])
    }

    func testRouteChangeDeliversOnlyOldDeviceUnavailable() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        let target = NSObject()
        var reasons: [IRAudioManagerRouteChangeReason] = []
        manager.setHandlerTarget(
            target,
            interruption: { _, _, _, _ in
                XCTFail("Unexpected interruption delivery")
            },
            routeChange: { handlerTarget, _, reason in
                XCTAssertTrue(handlerTarget === target)
                reasons.append(reason)
            }
        )

        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason
                    .oldDeviceUnavailable.rawValue
            ]
        )
        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason
                    .newDeviceAvailable.rawValue
            ]
        )

        XCTAssertEqual(reasons, [.oldDeviceUnavailable])
    }

    func testReplacingAndRemovingHandlerTargetIsDeterministic() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        let first = NSObject()
        let second = NSObject()
        var firstCalls = 0
        var secondCalls = 0

        manager.setHandlerTarget(
            first,
            interruption: { _, _, _, _ in firstCalls += 1 },
            routeChange: { _, _, _ in }
        )
        manager.setHandlerTarget(
            second,
            interruption: { _, _, _, _ in secondCalls += 1 },
            routeChange: { _, _, _ in }
        )
        manager.removeHandlerTarget(first)
        postBeganInterruption(to: center)
        manager.removeHandlerTarget(second)
        postBeganInterruption(to: center)
        manager.removeHandlerTarget(second)

        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func testReleasedHandlerTargetIsNotRetainedOrCalled() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        weak var weakTarget: NSObject?
        var calls = 0

        autoreleasepool {
            let target = NSObject()
            weakTarget = target
            manager.setHandlerTarget(
                target,
                interruption: { _, _, _, _ in calls += 1 },
                routeChange: { _, _, _ in }
            )
        }
        postBeganInterruption(to: center)

        XCTAssertNil(weakTarget)
        XCTAssertEqual(calls, 0)
    }

    func testMalformedNotificationsAreIgnored() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        let target = NSObject()
        var calls = 0
        manager.setHandlerTarget(
            target,
            interruption: { _, _, _, _ in calls += 1 },
            routeChange: { _, _, _ in calls += 1 }
        )

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [:]
        )
        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [:]
        )

        XCTAssertEqual(calls, 0)
    }

    func testManagerDeinitRemovesObserverTokensAndDoesNotRetainManager() {
        let center = NotificationCenter()
        let target = NSObject()
        weak var weakManager: IRAudioManager?
        var calls = 0

        autoreleasepool {
            var manager: IRAudioManager? = makeTestAudioManager(
                notificationCenter: center
            )
            weakManager = manager
            manager?.setHandlerTarget(
                target,
                interruption: { _, _, _, _ in calls += 1 },
                routeChange: { _, _, _ in }
            )
            manager = nil
        }
        postBeganInterruption(to: center)

        XCTAssertNil(weakManager)
        XCTAssertEqual(calls, 0)
    }

    func testConcurrentTargetReplacementRemovalAndDeliveryIsSafe() {
        let center = NotificationCenter()
        let manager = makeTestAudioManager(notificationCenter: center)
        let target = NSObject()
        let callLock = NSLock()
        var calls = 0
        let group = DispatchGroup()

        for index in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                manager.setHandlerTarget(
                    target,
                    interruption: { _, _, _, _ in
                        callLock.lock()
                        calls += 1
                        callLock.unlock()
                    },
                    routeChange: { _, _, _ in }
                )
                if index.isMultiple(of: 3) {
                    manager.removeHandlerTarget(target)
                }
                center.post(
                    name: AVAudioSession.interruptionNotification,
                    object: nil,
                    userInfo: [
                        AVAudioSessionInterruptionTypeKey:
                            AVAudioSession.InterruptionType.began.rawValue
                    ]
                )
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)

        manager.setHandlerTarget(
            target,
            interruption: { _, _, _, _ in
                callLock.lock()
                calls += 1
                callLock.unlock()
            },
            routeChange: { _, _, _ in }
        )
        callLock.lock()
        let beforeFinalDelivery = calls
        callLock.unlock()
        postBeganInterruption(to: center)
        callLock.lock()
        let finalCalls = calls
        callLock.unlock()
        XCTAssertEqual(finalCalls, beforeFinalDelivery + 1)
    }

    func testUnsignedIntegerRejectsNegativeFractionalAndBooleanPayloads() {
        XCTAssertNil(IRAudioManager.unsignedInteger(from: -1))
        XCTAssertNil(
            IRAudioManager.unsignedInteger(from: NSNumber(value: -1))
        )
        XCTAssertNil(
            IRAudioManager.unsignedInteger(from: NSNumber(value: 1.5))
        )
        XCTAssertNil(
            IRAudioManager.unsignedInteger(from: NSNumber(value: true))
        )
        XCTAssertNil(IRAudioManager.unsignedInteger(from: nil))
        XCTAssertNil(IRAudioManager.unsignedInteger(from: "invalid"))
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: 2), 2)
        XCTAssertEqual(IRAudioManager.unsignedInteger(from: UInt(3)), 3)
        XCTAssertEqual(
            IRAudioManager.unsignedInteger(from: NSNumber(value: 4)),
            4
        )
    }

    func testInterruptionEventMapsSupportedAVPayloads() throws {
        let begin = try XCTUnwrap(
            IRAudioManager.interruptionEvent(
                typeValue:
                    AVAudioSession.InterruptionType.began.rawValue,
                optionValue: nil
            )
        )
        XCTAssertEqual(begin.type, .begin)
        XCTAssertEqual(begin.option, .none)

        let ended = try XCTUnwrap(
            IRAudioManager.interruptionEvent(
                typeValue:
                    AVAudioSession.InterruptionType.ended.rawValue,
                optionValue:
                    AVAudioSession.InterruptionOptions
                    .shouldResume.rawValue
            )
        )
        XCTAssertEqual(ended.type, .ended)
        XCTAssertEqual(ended.option, .shouldResume)

        XCTAssertNil(
            IRAudioManager.interruptionEvent(
                typeValue: UInt.max,
                optionValue: nil
            )
        )
    }

    func testRouteChangeMapsOnlyOldDeviceUnavailable() {
        XCTAssertEqual(
            IRAudioManager.routeChangeReason(
                from:
                    AVAudioSession.RouteChangeReason
                    .oldDeviceUnavailable.rawValue
            ),
            .oldDeviceUnavailable
        )
        XCTAssertNil(
            IRAudioManager.routeChangeReason(
                from:
                    AVAudioSession.RouteChangeReason
                    .newDeviceAvailable.rawValue
            )
        )
        XCTAssertNil(IRAudioManager.routeChangeReason(from: UInt.max))
    }

    private func postBeganInterruption(to center: NotificationCenter) {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.began.rawValue
            ]
        )
    }
}

final class IRAudioManagerFacadeTests: XCTestCase {
    func testHardwareValuesAreFallbackUntilGraphIsPrepared() {
        let manager = makeTestAudioManager(
            sampleRate: 44_100,
            channels: 1
        )

        XCTAssertEqual(manager.samplingRate, 44_100)
        XCTAssertEqual(manager.numberOfChannels, 1)
        XCTAssertFalse(manager.playing)
        XCTAssertNil(manager.delegate)
    }

    func testRegisterIsIdempotentAndUnregisterAllowsNewGeneration() {
        let driver = TestAudioGraphDriver()
        let manager = makeTestAudioManager(driver: driver)

        XCTAssertTrue(manager.registerAudioSession())
        XCTAssertTrue(manager.registerAudioSession())
        XCTAssertEqual(driver.buildCount, 1)
        XCTAssertEqual(manager.diagnostics.phase, .ready)

        manager.unregisterAudioSession()
        XCTAssertEqual(driver.teardownCount, 1)
        XCTAssertEqual(manager.diagnostics.phase, .idle)

        XCTAssertTrue(manager.registerAudioSession())
        XCTAssertEqual(driver.buildCount, 2)
    }

    func testFailedRegistrationRemainsRetryable() {
        let driver = TestAudioGraphDriver()
        let issue = IRAudioGraphIssue(
            stage: .initializeGraph,
            status: -50
        )
        driver.replaceBuildResults([
            .failure(
                IRAudioGraphBuildFailure(
                    issue: issue,
                    cleanupIssues: []
                )
            ),
            .success(
                IRAudioGraphBuildOutput(
                    resources: makeTestAudioGraphResources(),
                    warnings: []
                )
            )
        ])
        let manager = makeTestAudioManager(driver: driver)

        XCTAssertFalse(manager.registerAudioSession())
        XCTAssertEqual(manager.diagnostics.phase, .idle)
        XCTAssertEqual(manager.diagnostics.lastBuildFailure?.issue, issue)
        XCTAssertTrue(manager.registerAudioSession())
        XCTAssertEqual(manager.diagnostics.phase, .ready)
        XCTAssertEqual(driver.buildCount, 2)
    }

    func testPlayAndPauseOwnDelegateAndRunningState() {
        let driver = TestAudioGraphDriver()
        let manager = makeTestAudioManager(driver: driver)
        let delegate = TestAudioManagerDelegate()

        XCTAssertTrue(manager.play(withDelegate: delegate))
        XCTAssertTrue(manager.playing)
        XCTAssertTrue(manager.delegate === delegate)
        XCTAssertEqual(driver.events, ["build", "start"])

        manager.pause()
        XCTAssertFalse(manager.playing)
        XCTAssertNil(manager.delegate)
        XCTAssertEqual(driver.events, ["build", "start", "stop"])
    }

    func testVolumeUsesOnlyPreparedMixerResource() {
        let driver = TestAudioGraphDriver()
        driver.setStoredVolume(0.75)
        let manager = makeTestAudioManager(driver: driver)

        manager.volume = 0.25
        XCTAssertEqual(manager.volume, 1)
        XCTAssertEqual(driver.setVolumes, [])

        XCTAssertTrue(manager.registerAudioSession())
        XCTAssertEqual(manager.volume, 0.75)
        manager.volume = 0.5
        XCTAssertEqual(driver.setVolumes, [0.5])
        XCTAssertEqual(manager.volume, 0.5)
    }
}
