import XCTest
@testable import IRPlayer_swift

final class IRPlayerLifecyclePolicyTests: XCTestCase {

    func testCommandTargetFollowsDecoderType() {
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .avPlayer), .avPlayer)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .ffmpeg), .ffmpeg)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .error), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: .none), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.commandTarget(for: nil), .none)
    }

    func testReplacementPlanStopsOppositeBackendAndSelectsReplacementTarget() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .avPlayer, hasAVPlayer: false, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: false, stopFFPlayer: true, replaceTarget: .avPlayer)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .ffmpeg, hasAVPlayer: true, hasFFPlayer: false),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: false, replaceTarget: .ffmpeg)
        )
    }

    func testReplacementPlanStopsExistingBackendsForInvalidDecoderTargets() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .error, hasAVPlayer: true, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: true, replaceTarget: .none)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: .none, hasAVPlayer: true, hasFFPlayer: true),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: true, replaceTarget: .none)
        )

        XCTAssertEqual(
            IRPlayerLifecyclePolicy.replacementPlan(for: nil, hasAVPlayer: true, hasFFPlayer: false),
            IRPlayerLifecyclePolicy.ReplacementPlan(stopAVPlayer: true, stopFFPlayer: false, replaceTarget: .none)
        )
    }

    func testBackgroundActionAutoPausesOnlyActivePlaybackStates() {
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .playing), .pauseAndRememberAutoPlay)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .buffering), .pauseAndRememberAutoPlay)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .readyToPlay), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .suspend), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .autoPlayAndPause, state: .failed), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .nothing, state: .playing), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.backgroundAction(mode: .continuing, state: .buffering), .none)
    }

    func testForegroundActionAutoResumesOnlySuspendedRememberedPlayback() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .suspend, needAutoPlay: true),
            .playAndClearAutoPlay
        )
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .suspend, needAutoPlay: false), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .autoPlayAndPause, state: .playing, needAutoPlay: true), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .nothing, state: .suspend, needAutoPlay: true), .none)
        XCTAssertEqual(IRPlayerLifecyclePolicy.foregroundAction(mode: .continuing, state: .suspend, needAutoPlay: true), .none)
    }

    func testAudioInterruptionActionPausesOnlyActivePlaybackOutsideForegroundGracePeriod() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioInterruptionAction(type: .begin, state: .playing, timeSinceForeground: 2),
            .pause
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioInterruptionAction(type: .begin, state: .buffering, timeSinceForeground: 2),
            .pause
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioInterruptionAction(type: .begin, state: .playing, timeSinceForeground: 1.5),
            .none
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioInterruptionAction(type: .ended, state: .playing, timeSinceForeground: 2),
            .none
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioInterruptionAction(type: .begin, state: .readyToPlay, timeSinceForeground: 2),
            .none
        )
    }

    func testAudioRouteChangeActionPausesOnlyActivePlaybackForOldDeviceUnavailable() {
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioRouteChangeAction(reason: .oldDeviceUnavailable, state: .playing),
            .pause
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioRouteChangeAction(reason: .oldDeviceUnavailable, state: .buffering),
            .pause
        )
        XCTAssertEqual(
            IRPlayerLifecyclePolicy.audioRouteChangeAction(reason: .oldDeviceUnavailable, state: .readyToPlay),
            .none
        )
    }
}
