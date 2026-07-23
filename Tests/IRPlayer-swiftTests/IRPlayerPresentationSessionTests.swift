import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRPlayerPresentationSessionTests: XCTestCase {
    func testInitializationBuildsOwnedDisplayAndControllers() {
        let (session, _) = makePresentationSession()

        let diagnostics = session.diagnostics
        XCTAssertTrue(diagnostics.hasDisplayView)
        XCTAssertTrue(diagnostics.hasGestureController)
        XCTAssertTrue(diagnostics.hasScrollController)
        XCTAssertFalse(diagnostics.hasMotionController)
        XCTAssertFalse(diagnostics.isClosed)
        XCTAssertGreaterThan(diagnostics.renderModeCount, 0)
        XCTAssertNotNil(diagnostics.currentMode)
        XCTAssertTrue(session.displayView?.abstractPlayer === session)
    }

    func testApplyingVRBoxOwnsMotionAndReturningToNormalStopsIt() {
        let (session, motion) = makePresentationSession()

        session.apply(videoType: .vr, displayMode: .box)

        XCTAssertTrue(
            session.currentRenderMode is IRGLRenderModeDistortion
        )
        XCTAssertEqual(session.viewGravityMode, .resizeAspect)
        XCTAssertTrue(session.diagnostics.hasMotionController)
        XCTAssertTrue(motion.targetView === session.displayView)
        XCTAssertEqual(motion.resetCount, 1)

        session.apply(videoType: .normal, displayMode: .normal)

        XCTAssertFalse(session.diagnostics.hasMotionController)
        XCTAssertGreaterThanOrEqual(motion.stopCount, 1)
    }

    func testSetAndSelectRenderModesSynchronizesCurrentMode() {
        let (session, _) = makePresentationSession()
        let first = IRGLRenderModeFactory.createVRMode(with: nil)
        let second = IRGLRenderModeFactory.createDistortionMode(with: nil)

        session.setRenderModes([first, second])

        XCTAssertTrue(session.currentRenderMode === first)
        XCTAssertTrue(session.selectRenderMode(second))
        XCTAssertTrue(session.currentRenderMode === second)

        let unregistered = IRGLRenderModeFactory.createNormalModes(
            with: nil
        )[0]
        XCTAssertFalse(session.selectRenderMode(unregistered))
        XCTAssertTrue(session.currentRenderMode === second)
    }

    func testTapHandlerDeliversOwnedViewExactlyOncePerTap() {
        let (session, _) = makePresentationSession()
        var deliveredViews: [IRPLFView] = []
        session.setTapHandler { deliveredViews.append($0) }

        session.handleSingleTap()
        session.handleSingleTap()

        XCTAssertEqual(deliveredViews.count, 2)
        XCTAssertTrue(deliveredViews[0] === session.displayView)
        XCTAssertTrue(deliveredViews[1] === session.displayView)
    }

    func testPlayerSubviewReplacementAndSnapshotAreMainThreadSafe() {
        let (session, _) = makePresentationSession()
        let first = UIView()
        let second = UIView()

        let finished = expectation(description: "background UI request")
        DispatchQueue.global(qos: .userInitiated).async {
            session.attachPlayerView(first)
            session.attachPlayerView(second)
            session.updateFrame(
                CGRect(x: 0, y: 0, width: 16, height: 9)
            )
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertNil(first.superview)
        XCTAssertTrue(second.superview === session.displayView)
        XCTAssertEqual(session.displayView?.subviews, [second])
        XCTAssertEqual(session.snapshot()?.size, CGSize(width: 16, height: 9))
    }

    func testGravityChangesAreOwnedBySession() {
        let (session, _) = makePresentationSession()

        session.setGravityMode(.resizeAspectFill)

        XCTAssertEqual(session.viewGravityMode, .resizeAspectFill)
        XCTAssertEqual(session.diagnostics.gravityMode, .resizeAspectFill)
    }

    func testCloseIsTerminalIdempotentAndDrainsInteractionOwners() {
        let (session, motion) = makePresentationSession()
        session.apply(videoType: .vr, displayMode: .box)
        var tapCount = 0
        session.setTapHandler { _ in tapCount += 1 }

        XCTAssertTrue(session.close())
        XCTAssertFalse(session.close())
        session.handleSingleTap()
        session.setGravityMode(.resize)

        let diagnostics = session.diagnostics
        XCTAssertTrue(diagnostics.isClosed)
        XCTAssertFalse(diagnostics.hasDisplayView)
        XCTAssertFalse(diagnostics.hasGestureController)
        XCTAssertFalse(diagnostics.hasScrollController)
        XCTAssertFalse(diagnostics.hasMotionController)
        XCTAssertEqual(tapCount, 0)
        XCTAssertGreaterThanOrEqual(motion.stopCount, 1)
    }

    private func makePresentationSession() -> (
        IRPlayerPresentationSession,
        PresentationMotionProbe
    ) {
        let motion = PresentationMotionProbe()
        let dependencies = IRPlayerPresentationDependencies(
            displayFactory: {
                IRGLView(frame: .zero, player: $0)
            },
            gestureFactory: { IRGLGestureController() },
            scrollFactory: {
                IRSmoothScrollController(targetView: $0)
            },
            motionFactory: { motion }
        )
        return (
            IRPlayerPresentationSession(dependencies: dependencies),
            motion
        )
    }
}

private final class PresentationMotionProbe:
    IRPlayerMotionControlling
{
    var targetView: IRGLView?
    var smoothScroll: IRSmoothScrollController?
    private(set) var resetCount = 0
    private(set) var stopCount = 0

    func resetUnit() -> Bool {
        resetCount += 1
        return true
    }

    func stopMotionDetection() {
        stopCount += 1
    }
}
