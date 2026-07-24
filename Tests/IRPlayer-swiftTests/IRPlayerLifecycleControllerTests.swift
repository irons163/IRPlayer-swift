import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRPlayerLifecycleControllerTests: XCTestCase {
    func testBackgroundAndForegroundOwnResumeIntentAsOneStateTransition() {
        let controller = IRPlayerLifecycleController()

        XCTAssertEqual(controller.didEnterBackground(state: .playing), .pause)
        XCTAssertTrue(controller.needsForegroundResume)
        XCTAssertEqual(controller.willEnterForeground(state: .suspend, now: 10), .play)
        XCTAssertFalse(controller.needsForegroundResume)
        XCTAssertEqual(controller.lastForegroundTime, 10)
    }

    func testInactiveBackgroundDoesNotCreateResumeIntent() {
        let controller = IRPlayerLifecycleController()

        XCTAssertEqual(controller.didEnterBackground(state: .readyToPlay), .none)
        XCTAssertEqual(controller.willEnterForeground(state: .suspend, now: 10), .none)
        XCTAssertFalse(controller.needsForegroundResume)
        XCTAssertNil(controller.lastForegroundTime)
    }

    func testContinuePlaybackModeIgnoresEnvironmentTransitions() {
        let controller = IRPlayerLifecycleController(mode: .continuing)

        XCTAssertEqual(controller.didEnterBackground(state: .playing), .none)
        XCTAssertEqual(controller.willEnterForeground(state: .suspend, now: 10), .none)
    }

    func testAudioInterruptionHonorsForegroundGracePeriod() {
        let controller = IRPlayerLifecycleController()
        _ = controller.didEnterBackground(state: .playing)
        _ = controller.willEnterForeground(state: .suspend, now: 10)

        XCTAssertEqual(controller.audioInterruption(type: .begin, state: .playing, now: 11), .none)
        XCTAssertEqual(controller.audioInterruption(type: .begin, state: .playing, now: 12), .pause)
        XCTAssertEqual(controller.audioInterruption(type: .ended, state: .playing, now: 12), .none)
    }

    func testRouteChangeAndResetAreDeterministic() {
        let controller = IRPlayerLifecycleController()
        _ = controller.didEnterBackground(state: .buffering)

        XCTAssertEqual(
            controller.audioRouteChanged(reason: .oldDeviceUnavailable, state: .buffering),
            .pause
        )
        controller.reset()
        XCTAssertFalse(controller.needsForegroundResume)
        XCTAssertNil(controller.lastForegroundTime)
    }
}
