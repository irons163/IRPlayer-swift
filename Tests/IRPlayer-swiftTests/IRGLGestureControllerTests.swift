import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGLGestureControllerTests: XCTestCase {

    func testGesturePolicyConvertsTouchPointToRenderSpace() {
        let point = IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                                 viewHeight: 100,
                                                 screenScale: 3)

        XCTAssertEqual(point.x, 36)
        XCTAssertEqual(point.y, 240)
    }

    func testGesturePolicyDefaultsInvalidInputsToZero() {
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: CGFloat.nan, y: 20),
                                          viewHeight: 100,
                                          screenScale: 3),
            .zero
        )
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                          viewHeight: CGFloat.infinity,
                                          screenScale: 3),
            .zero
        )
        XCTAssertEqual(
            IRGLGesturePolicy.renderPoint(from: CGPoint(x: 12, y: 20),
                                          viewHeight: 100,
                                          screenScale: 0),
            .zero
        )
    }

    func testSmoothScrollTargetScalesVelocityMagnitudeIntoDistanceAndDuration() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: CGPoint(x: 300, y: 400))

        XCTAssertEqual(target.point.x, 37.5, accuracy: 0.0001)
        XCTAssertEqual(target.point.y, 50, accuracy: 0.0001)
        XCTAssertEqual(target.duration, 0.25, accuracy: 0.0001)
    }

    func testSmoothScrollTargetUsesZeroForZeroVelocity() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: .zero)

        XCTAssertEqual(target.point, .zero)
        XCTAssertEqual(target.duration, 0)
    }

    func testSmoothScrollTargetDefaultsNonFiniteVelocityToZero() {
        let target = IRSmoothScrollController.smoothScrollTarget(for: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))

        XCTAssertEqual(target.point, .zero)
        XCTAssertEqual(target.duration, 0)
    }

    func testClearingCurrentModeClearsSmoothScrollMode() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()

        gestureController.smoothScroll = smoothScroll
        gestureController.currentMode = IRGLRenderMode2D()

        gestureController.currentMode = nil

        XCTAssertNil(smoothScroll.currentMode)
        withExtendedLifetime(smoothScroll) {}
    }

    func testAddGestureReplacesExistingRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.addGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertEqual(rotationRecognizers.count, 1)
    }

    func testRemoveGestureRemovesRotationGestureRecognizer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()

        gestureController.addGesture(to: view)
        gestureController.removeGesture(to: view)

        let rotationRecognizers = view.gestureRecognizers?.filter { $0 is UIRotationGestureRecognizer } ?? []
        XCTAssertTrue(rotationRecognizers.isEmpty)
    }
}

final class IRBounceControllerTests: XCTestCase {

    func testBounceGeometryClampsHorizontalControlPointToBounceWidth() {
        let geometry = IRBounceController.bouncePathGeometry(amount: -200,
                                                             direction: .left,
                                                             targetSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(geometry.start, CGPoint(x: 100, y: 0))
        XCTAssertEqual(geometry.control, CGPoint(x: 92, y: 40))
        XCTAssertEqual(geometry.end, CGPoint(x: 100, y: 80))
    }

    func testBounceGeometryClampsVerticalControlPointToBounceWidth() {
        let geometry = IRBounceController.bouncePathGeometry(amount: 200,
                                                             direction: .down,
                                                             targetSize: CGSize(width: 100, height: 80))

        XCTAssertEqual(geometry.start, .zero)
        XCTAssertEqual(geometry.control, CGPoint(x: 50, y: 8))
        XCTAssertEqual(geometry.end, CGPoint(x: 100, y: 0))
    }
}
