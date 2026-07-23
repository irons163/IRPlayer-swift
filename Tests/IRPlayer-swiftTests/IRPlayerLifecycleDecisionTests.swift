import XCTest
@testable import IRPlayer_swift

final class IRPlayerLifecycleDecisionTests: XCTestCase {
    func testBackgroundDecisionPausesOnlyActiveAutomaticPlayback() {
        for state in [IRPlayerState.playing, .buffering] {
            let controller = IRPlayerLifecycleController()
            XCTAssertEqual(controller.didEnterBackground(state: state), .pause)
            XCTAssertTrue(controller.needsForegroundResume)
        }

        for state in [
            IRPlayerState.none,
            .readyToPlay,
            .suspend,
            .finished,
            .failed
        ] {
            let controller = IRPlayerLifecycleController()
            XCTAssertEqual(controller.didEnterBackground(state: state), .none)
            XCTAssertFalse(controller.needsForegroundResume)
        }
    }

    func testNonAutomaticModesIgnoreBackgroundAndForeground() {
        for mode in [
            IRPlayerBackgroundMode.nothing,
            .continuing
        ] {
            let controller = IRPlayerLifecycleController(mode: mode)
            XCTAssertEqual(
                controller.didEnterBackground(state: .playing),
                .none
            )
            XCTAssertEqual(
                controller.willEnterForeground(state: .suspend, now: 10),
                .none
            )
            XCTAssertFalse(controller.needsForegroundResume)
        }
    }

    func testForegroundDecisionConsumesResumeIntentOnlyWhenSuspended() {
        let controller = IRPlayerLifecycleController()
        XCTAssertEqual(
            controller.didEnterBackground(state: .playing),
            .pause
        )
        XCTAssertEqual(
            controller.willEnterForeground(state: .playing, now: 10),
            .none
        )
        XCTAssertTrue(controller.needsForegroundResume)
        XCTAssertEqual(
            controller.willEnterForeground(state: .suspend, now: 11),
            .play
        )
        XCTAssertFalse(controller.needsForegroundResume)
        XCTAssertEqual(controller.lastForegroundTime, 11)
    }

    func testInterruptionBoundaryAndInactiveStatesAreDeterministic() {
        let controller = IRPlayerLifecycleController()
        _ = controller.didEnterBackground(state: .playing)
        _ = controller.willEnterForeground(state: .suspend, now: 10)

        XCTAssertEqual(
            controller.audioInterruption(
                type: .begin,
                state: .playing,
                now: 11.499
            ),
            .none
        )
        XCTAssertEqual(
            controller.audioInterruption(
                type: .begin,
                state: .playing,
                now: 11.501
            ),
            .pause
        )
        XCTAssertEqual(
            controller.audioInterruption(
                type: .begin,
                state: .buffering,
                now: 12
            ),
            .pause
        )
        XCTAssertEqual(
            controller.audioInterruption(
                type: .ended,
                state: .playing,
                now: 12
            ),
            .none
        )
        XCTAssertEqual(
            controller.audioInterruption(
                type: .begin,
                state: .readyToPlay,
                now: 12
            ),
            .none
        )
    }

    func testRouteDecisionPausesOnlyActivePlaybackForUnavailableDevice() {
        for state in [IRPlayerState.playing, .buffering] {
            let controller = IRPlayerLifecycleController()
            XCTAssertEqual(
                controller.audioRouteChanged(
                    reason: .oldDeviceUnavailable,
                    state: state
                ),
                .pause
            )
        }

        let controller = IRPlayerLifecycleController()
        XCTAssertEqual(
            controller.audioRouteChanged(
                reason: .oldDeviceUnavailable,
                state: .readyToPlay
            ),
            .none
        )
    }
}
