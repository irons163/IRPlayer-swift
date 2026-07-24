//
//  IRSmoothScrollControllerTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/7/24.
//

import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRSmoothScrollControllerTests: XCTestCase {
    func testInitializationInstallsPausedDisplayLinkAndBounce() {
        let fixture = SmoothScrollControllerFixture()

        XCTAssertEqual(fixture.driver.installCount, 1)
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertTrue(
            fixture.controller.targetView === fixture.view
        )
        XCTAssertTrue(
            fixture.bounce.installedView === fixture.view
        )
    }

    func testInstallationFailureRejectsAnimation() {
        let fixture = SmoothScrollControllerFixture(
            installsSuccessfully: false
        )

        XCTAssertFalse(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )
        XCTAssertFalse(
            fixture.controller.diagnostics
                .isDisplayLinkInstalled
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .uninstalled
        )
    }

    func testActivationFailureReturnsSessionToIdle() {
        let fixture = SmoothScrollControllerFixture(
            activatesSuccessfully: false
        )

        XCTAssertFalse(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .idle
        )
    }

    func testVelocityStartsAndResetPausesRuntime() {
        let fixture = SmoothScrollControllerFixture()
        fixture.controller.isPaned = true

        XCTAssertTrue(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .active
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.finalPoint,
            CGPoint(x: 37.5, y: 50)
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.duration,
            0.25,
            accuracy: 0.0001
        )

        fixture.controller.resetSmoothScroll()

        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
    }

    func testZeroAndInvalidVelocityStayIdle() {
        let fixture = SmoothScrollControllerFixture()

        XCTAssertFalse(
            fixture.controller.calculateSmoothScroll(
                velocity: .zero
            )
        )
        XCTAssertFalse(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(
                    x: CGFloat.nan,
                    y: CGFloat.infinity
                )
            )
        )
        XCTAssertFalse(
            fixture.driver.activeRequests.contains(true)
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
    }

    func testControlledTicksCompleteAndNotifyOnce() {
        let fixture = SmoothScrollControllerFixture()
        let delegate = SmoothScrollDelegateProbe()
        fixture.controller.delegate = delegate
        fixture.controller.isPaned = true
        XCTAssertTrue(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        fixture.driver.emit(timestamp: 10)
        fixture.driver.emit(timestamp: 10.125)
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.alreadyPoint.x,
            28.125,
            accuracy: 0.0001
        )

        fixture.driver.emit(timestamp: 10.25)
        fixture.driver.emitRegardless(timestamp: 10.5)

        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertEqual(
            delegate.endDeceleratingViews.count,
            1
        )
        XCTAssertTrue(
            delegate.endDeceleratingViews[0]
                === fixture.view
        )
    }

    func testResetRejectsCapturedStaleTick() {
        let fixture = SmoothScrollControllerFixture()
        let delegate = SmoothScrollDelegateProbe()
        fixture.controller.delegate = delegate
        XCTAssertTrue(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )
        fixture.controller.resetSmoothScroll()

        fixture.driver.emitRegardless(timestamp: 12)

        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertTrue(
            delegate.endDeceleratingViews.isEmpty
        )
    }

    func testDegreeShiftComposesPendingRemainder() {
        let fixture = SmoothScrollControllerFixture()
        fixture.controller.isPaned = true
        XCTAssertTrue(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        fixture.controller.shiftDegreeX(
            10,
            degreeY: 5
        )

        let animation =
            fixture.controller.diagnostics.animation
        XCTAssertEqual(
            animation.finalPoint,
            CGPoint(x: 47.5, y: 45)
        )
        XCTAssertEqual(
            animation.duration,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertFalse(animation.isPaned)
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .active
        )
    }

    func testInvalidDegreeShiftPausesAndClearsWork() {
        let fixture = SmoothScrollControllerFixture()
        fixture.controller.shiftDegreeX(
            10,
            degreeY: 5
        )

        fixture.controller.shiftDegreeX(
            .nan,
            degreeY: 1
        )

        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .idle
        )
    }

    func testDegreeCompletionDoesNotReportGestureDeceleration() {
        let fixture = SmoothScrollControllerFixture()
        let delegate = SmoothScrollDelegateProbe()
        fixture.controller.delegate = delegate
        fixture.controller.shiftDegreeX(
            10,
            degreeY: 5
        )

        fixture.driver.emit(timestamp: 20)
        fixture.driver.emit(timestamp: 20.5)

        XCTAssertEqual(
            fixture.controller.diagnostics
                .animation.phase,
            .idle
        )
        XCTAssertTrue(
            delegate.endDeceleratingViews.isEmpty
        )
    }

    func testBoundsRequestsAnimateOncePerAxisAndNotify() {
        let fixture = SmoothScrollControllerFixture()
        let delegate = SmoothScrollDelegateProbe()
        fixture.controller.delegate = delegate
        fixture.controller.shiftDegreeX(
            30,
            degreeY: 40
        )

        fixture.controller.didScrollToBounds(
            .both,
            withProgram: IRGLProgram2D()
        )
        fixture.controller.didScrollToBounds(
            .both,
            withProgram: IRGLProgram2D()
        )

        XCTAssertEqual(
            fixture.bounce.requests,
            [
                SmoothScrollBounceRequest(
                    amount: 30,
                    direction: .right
                ),
                SmoothScrollBounceRequest(
                    amount: -40,
                    direction: .up
                )
            ]
        )
        XCTAssertEqual(
            delegate.boundsScrollViews.count,
            2
        )
        XCTAssertTrue(
            fixture.controller.diagnostics
                .animation
                .didHorizontalBoundsBounce
        )
        XCTAssertTrue(
            fixture.controller.diagnostics
                .animation
                .didVerticalBoundsBounce
        )
    }

    func testCloseIsTerminalAndRepeatable() {
        let fixture = SmoothScrollControllerFixture()
        XCTAssertTrue(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertTrue(fixture.controller.close())
        XCTAssertFalse(fixture.controller.close())
        XCTAssertFalse(
            fixture.controller.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
        )

        XCTAssertEqual(fixture.driver.closeCount, 1)
        XCTAssertEqual(
            fixture.driver.snapshot.phase,
            .closed
        )
        XCTAssertTrue(
            fixture.controller.diagnostics.isClosed
        )
        XCTAssertFalse(
            fixture.controller.diagnostics.hasTargetView
        )
    }

    func testDriverHandlerDoesNotRetainController() {
        let driver = SmoothScrollDisplayLinkProbe()
        let bounce = SmoothScrollBounceProbe()
        weak var weakController:
            IRSmoothScrollController?

        autoreleasepool {
            var controller:
                IRSmoothScrollController? =
                    IRSmoothScrollController(
                        targetView:
                            IRGLView(frame: .zero),
                        dependencies:
                            IRSmoothScrollDependencies(
                                displayLink: driver,
                                bounce: bounce,
                                screenScale: { 1 }
                            )
                    )
            weakController = controller
            _ = controller?.calculateSmoothScroll(
                velocity: CGPoint(x: 300, y: 400)
            )
            controller = nil
        }

        XCTAssertNil(weakController)
        XCTAssertEqual(driver.closeCount, 1)
        driver.emitRegardless(timestamp: 1)
    }
}

private final class SmoothScrollControllerFixture {
    let driver: SmoothScrollDisplayLinkProbe
    let bounce: SmoothScrollBounceProbe
    let view: IRGLView
    let controller: IRSmoothScrollController

    init(
        installsSuccessfully: Bool = true,
        activatesSuccessfully: Bool = true
    ) {
        driver = SmoothScrollDisplayLinkProbe(
            installsSuccessfully: installsSuccessfully,
            activatesSuccessfully:
                activatesSuccessfully
        )
        bounce = SmoothScrollBounceProbe()
        view = IRGLView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 120,
                height: 80
            )
        )
        controller = IRSmoothScrollController(
            targetView: view,
            dependencies: IRSmoothScrollDependencies(
                displayLink: driver,
                bounce: bounce,
                screenScale: { 1 }
            )
        )
    }
}

private final class SmoothScrollDisplayLinkProbe:
    IRSmoothScrollDisplayLinkDriving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let installsSuccessfully: Bool
    private let activatesSuccessfully: Bool
    private var storedSnapshot =
        IRSmoothScrollDisplayLinkSnapshot(
            phase: .uninstalled,
            scheduledMode: nil
        )
    private var handler:
        ((TimeInterval) -> Void)?
    private(set) var installCount = 0
    private(set) var closeCount = 0
    private(set) var activeRequests: [Bool] = []

    init(
        installsSuccessfully: Bool = true,
        activatesSuccessfully: Bool = true
    ) {
        self.installsSuccessfully =
            installsSuccessfully
        self.activatesSuccessfully =
            activatesSuccessfully
    }

    var snapshot:
        IRSmoothScrollDisplayLinkSnapshot
    {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    @discardableResult
    func install(
        handler: @escaping (TimeInterval) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        installCount += 1
        guard installsSuccessfully,
              storedSnapshot.phase == .uninstalled else {
            return false
        }
        self.handler = handler
        storedSnapshot =
            IRSmoothScrollDisplayLinkSnapshot(
                phase: .idle,
                scheduledMode:
                    RunLoop.Mode.common.rawValue
            )
        return true
    }

    @discardableResult
    func setActive(_ isActive: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedSnapshot.phase == .idle
                || storedSnapshot.phase == .active,
              !isActive || activatesSuccessfully else {
            return false
        }
        activeRequests.append(isActive)
        storedSnapshot =
            IRSmoothScrollDisplayLinkSnapshot(
                phase: isActive ? .active : .idle,
                scheduledMode:
                    RunLoop.Mode.common.rawValue
            )
        return true
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedSnapshot.phase != .closed else {
            return false
        }
        closeCount += 1
        storedSnapshot =
            IRSmoothScrollDisplayLinkSnapshot(
                phase: .closed,
                scheduledMode: nil
            )
        return true
    }

    func emit(timestamp: TimeInterval) {
        let handler: ((TimeInterval) -> Void)?
        lock.lock()
        handler = storedSnapshot.phase == .active
            ? self.handler
            : nil
        lock.unlock()
        handler?(timestamp)
    }

    func emitRegardless(timestamp: TimeInterval) {
        let handler: ((TimeInterval) -> Void)?
        lock.lock()
        handler = self.handler
        lock.unlock()
        handler?(timestamp)
    }
}

private struct SmoothScrollBounceRequest: Equatable {
    let amount: CGFloat
    let direction: IRScrollDirectionType
}

private final class SmoothScrollBounceProbe:
    IRSmoothScrollBounceDriving
{
    private(set) weak var installedView: UIView?
    private(set) var requests:
        [SmoothScrollBounceRequest] = []

    func install(on view: UIView) {
        installedView = view
    }

    func animate(
        amount: CGFloat,
        direction: IRScrollDirectionType
    ) {
        requests.append(
            SmoothScrollBounceRequest(
                amount: amount,
                direction: direction
            )
        )
    }
}

private final class SmoothScrollDelegateProbe:
    IRGLViewDelegate
{
    private(set) var endDeceleratingViews:
        [IRGLView?] = []
    private(set) var boundsScrollViews: [IRGLView?] = []

    func glViewDidEndDragging(
        _ view: IRGLView?,
        willDecelerate: Bool
    ) {}

    func glViewWillBeginDragging(_ view: IRGLView?) {}
    func glViewWillBeginZooming(_ view: IRGLView?) {}

    func glViewDidEndDecelerating(_ view: IRGLView?) {
        endDeceleratingViews.append(view)
    }

    func glViewDidEndZooming(
        _ view: IRGLView?,
        atScale scale: CGFloat
    ) {}

    func glViewDidScroll(toBounds view: IRGLView?) {
        boundsScrollViews.append(view)
    }
}
