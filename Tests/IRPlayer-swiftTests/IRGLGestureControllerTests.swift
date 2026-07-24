import UIKit
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRGLGestureControllerTests: XCTestCase {

    func testRenderPointConvertsViewPointToRenderSpace() {
        let point = IRGLGestureController.renderPoint(
            from: CGPoint(x: 12, y: 20),
            viewHeight: 100,
            screenScale: 3
        )

        XCTAssertEqual(point.x, 36)
        XCTAssertEqual(point.y, 240)
    }

    func testRenderPointDefaultsInvalidInputsToZero() {
        XCTAssertEqual(
            IRGLGestureController.renderPoint(
                from: CGPoint(x: CGFloat.nan, y: 20),
                viewHeight: 100,
                screenScale: 3
            ),
            .zero
        )
        XCTAssertEqual(
            IRGLGestureController.renderPoint(
                from: CGPoint(x: 12, y: 20),
                viewHeight: CGFloat.infinity,
                screenScale: 3
            ),
            .zero
        )
        XCTAssertEqual(
            IRGLGestureController.renderPoint(
                from: CGPoint(x: 12, y: 20),
                viewHeight: 100,
                screenScale: 0
            ),
            .zero
        )
        XCTAssertEqual(
            IRGLGestureController.renderPoint(
                from: CGPoint(x: 12, y: 20),
                viewHeight: 100,
                screenScale: -1
            ),
            .zero
        )
    }

    func testRenderPointRejectsDerivedCoordinateOverflow() {
        XCTAssertEqual(
            IRGLGestureController.renderPoint(
                from: CGPoint(
                    x: CGFloat.greatestFiniteMagnitude,
                    y: -CGFloat.greatestFiniteMagnitude
                ),
                viewHeight: CGFloat.greatestFiniteMagnitude,
                screenScale: CGFloat.greatestFiniteMagnitude
            ),
            .zero
        )
    }

    func testPanActionCoversEveryKnownRecognizerState() {
        let cases: [
            (
                UIGestureRecognizer.State,
                IRGLGestureController.PanAction
            )
        ] = [
            (.possible, .update),
            (.began, .begin),
            (.changed, .update),
            (.ended, .endWithDeceleration),
            (.cancelled, .cancel),
            (.failed, .cancel)
        ]

        for (state, expected) in cases {
            XCTAssertEqual(
                IRGLGestureController.glPanAction(for: state),
                expected
            )
        }
    }

    func testContinuousActionCoversEveryKnownRecognizerState() {
        let cases: [
            (
                UIGestureRecognizer.State,
                IRGLGestureController.ContinuousAction
            )
        ] = [
            (.possible, .update),
            (.began, .begin),
            (.changed, .update),
            (.ended, .end),
            (.cancelled, .end),
            (.failed, .end)
        ]

        for (state, expected) in cases {
            XCTAssertEqual(
                IRGLGestureController.continuousAction(
                    for: state
                ),
                expected
            )
        }
    }

    func testShouldBeginRejectsDisabledOrConflictingGestures() {
        XCTAssertFalse(
            IRGLGestureController.shouldBeginGesture(
                superAllowsGesture: false,
                isDoubleTapGesture: false,
                doubleTapEnabled: true,
                isSwipeGesture: false,
                isProgramZooming: false
            )
        )
        XCTAssertFalse(
            IRGLGestureController.shouldBeginGesture(
                superAllowsGesture: true,
                isDoubleTapGesture: true,
                doubleTapEnabled: false,
                isSwipeGesture: false,
                isProgramZooming: false
            )
        )
        XCTAssertFalse(
            IRGLGestureController.shouldBeginGesture(
                superAllowsGesture: true,
                isDoubleTapGesture: false,
                doubleTapEnabled: true,
                isSwipeGesture: true,
                isProgramZooming: true
            )
        )
        XCTAssertTrue(
            IRGLGestureController.shouldBeginGesture(
                superAllowsGesture: true,
                isDoubleTapGesture: true,
                doubleTapEnabled: true,
                isSwipeGesture: true,
                isProgramZooming: false
            )
        )
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

    func testGestureCallbacksDoNotWriteDebugOutput() {
        let gestureController = IRGLGestureController()

        let output = captureStandardOutput {
            gestureController.handlePan(UIPanGestureRecognizer())
            gestureController.handlePinch(UIPinchGestureRecognizer())
            gestureController.handleRotate(UIRotationGestureRecognizer())
            gestureController.handleDoubleTap(UITapGestureRecognizer())
        }

        XCTAssertEqual(output, "")
    }

    func testProgramZoomingDefaultsToFalseWithoutCurrentMode() {
        let gestureController = IRGLGestureController()

        XCTAssertFalse(gestureController.isProgramZooming())
    }

    func testProgramZoomingReturnsTrueWhenProgramScaleDiffersFromDefault() {
        let gestureController = IRGLGestureController()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D()

        program.tramsformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 2,
                                                                                      scaleY: 1,
                                                                                      offsetX: 0,
                                                                                      offsetY: 0,
                                                                                      panDegree: 0,
                                                                                      w: 200,
                                                                                      h: 100))
        mode.program = program
        gestureController.currentMode = mode

        XCTAssertTrue(gestureController.isProgramZooming())
    }

    func testProgramCreationAssignsSmoothScrollAsProgramDelegate() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()
        let program = IRGLProgram2D()

        gestureController.smoothScroll = smoothScroll
        gestureController.programDidCreate(program)

        XCTAssertTrue(program.delegate === smoothScroll)
        withExtendedLifetime(smoothScroll) {}
    }

    func testGestureShouldBeginRejectsDisabledDoubleTapWithoutCurrentProgram() {
        let gestureController = IRGLGestureController()

        gestureController.doubleTapEnable = false

        XCTAssertFalse(gestureController.gestureRecognizerShouldBegin(gestureController.doubleTapGR))
    }

    func testSimultaneousRecognitionAllowsSwipeWithPanWhenNotZooming() {
        let gestureController = IRGLGestureController()

        XCTAssertTrue(
            gestureController.gestureRecognizer(
                gestureController.panGR,
                shouldRecognizeSimultaneouslyWith: UISwipeGestureRecognizer()
            )
        )
    }

    func testSimultaneousRecognitionFallsBackWhenSwipeIsDisabled() {
        let gestureController = IRGLGestureController()

        gestureController.swipeEnable = false

        XCTAssertFalse(
            gestureController.gestureRecognizer(
                gestureController.panGR,
                shouldRecognizeSimultaneouslyWith: UISwipeGestureRecognizer()
            )
        )
    }

    func testPanHandlerNotifiesDelegateForCancelAndEndStates() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll =
            IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()
        let delegate = RecordingGLViewDelegate()
        let pan = GLStubPanGestureRecognizer()

        gestureController.delegate = delegate
        gestureController.smoothScroll = smoothScroll
        gestureController.addGesture(to: view)

        pan.stubState = .cancelled
        gestureController.handlePan(pan)

        pan.stubState = .ended
        pan.stubVelocity = .zero
        gestureController.handlePan(pan)

        pan.stubVelocity = CGPoint(x: 300, y: 400)
        gestureController.handlePan(pan)

        pan.stubVelocity = CGPoint(
            x: CGFloat.nan,
            y: 1
        )
        gestureController.handlePan(pan)

        XCTAssertEqual(
            delegate.endDraggingWillDecelerate,
            [false, false, true, false]
        )
        XCTAssertTrue(delegate.endDraggingViews.allSatisfy { $0 === view })
        withExtendedLifetime(smoothScroll) {}
    }

    func testPanHandlerCoversBeginAndIgnoredUpdateWhenTouchIsOutsideProgram() {
        let gestureController = IRGLGestureController()
        let pan = GLStubPanGestureRecognizer()

        pan.stubState = .began
        pan.stubLocation = CGPoint(x: 10, y: 10)
        gestureController.handlePan(pan)

        pan.stubState = .changed
        pan.stubTranslation = CGPoint(x: 6, y: -2)
        gestureController.handlePan(pan)

        XCTAssertEqual(pan.stubTranslation, CGPoint(x: 6, y: -2))
    }

    func testPanHandlerScrollsProgramWhenTouchBeginsInsideProgram() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let smoothScroll = IRSmoothScrollController(targetView: view)
        let gestureController = IRGLGestureController()
        let delegate = RecordingGLViewDelegate()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000),
            parameter: nil
        )
        let transformController = RecordingTransformController()
        let pan = GLStubPanGestureRecognizer()
        let screenScale = UIScreen.main.scale

        program.tramsformController = transformController
        mode.program = program
        view.mode = mode
        gestureController.delegate = delegate
        gestureController.smoothScroll = smoothScroll
        gestureController.addGesture(to: view)
        gestureController.currentMode = mode

        pan.stubLocation = CGPoint(x: 10, y: 10)
        pan.stubState = .began
        gestureController.handlePan(pan)

        pan.stubState = .changed
        pan.stubTranslation = CGPoint(x: 3, y: -4)
        gestureController.handlePan(pan)

        XCTAssertEqual(delegate.beginDraggingViews.count, 1)
        XCTAssertTrue(delegate.beginDraggingViews[0] === view)
        XCTAssertEqual(transformController.scrollOffsets.count, 1)
        XCTAssertEqual(transformController.scrollOffsets[0].dx, Float(3 * screenScale), accuracy: 0.0001)
        XCTAssertEqual(transformController.scrollOffsets[0].dy, Float(4 * screenScale), accuracy: 0.0001)
        XCTAssertEqual(pan.stubTranslation, .zero)
        withExtendedLifetime(smoothScroll) {}
    }

    func testPinchAndRotateHandlersCoverEndBeginAndIgnoredUpdateStates() {
        let gestureController = IRGLGestureController()
        let pinch = GLStubPinchGestureRecognizer()
        let rotation = GLStubRotationGestureRecognizer()

        pinch.stubState = .ended
        gestureController.handlePinch(pinch)
        pinch.stubState = .began
        gestureController.handlePinch(pinch)
        pinch.stubState = .changed
        gestureController.handlePinch(pinch)

        rotation.stubState = .ended
        gestureController.handleRotate(rotation)
        rotation.stubState = .began
        gestureController.handleRotate(rotation)
        rotation.stubState = .changed
        rotation.rotation = 0.5
        gestureController.handleRotate(rotation)

        XCTAssertEqual(rotation.rotation, 0.5)
    }

    func testPinchHandlerUpdatesProgramScopeWhenTwoTouchesBeginInsideProgram() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()
        let delegate = RecordingGLViewDelegate()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000),
            parameter: nil
        )
        let transformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 1,
                                                                                  scaleY: 1,
                                                                                  offsetX: 0,
                                                                                  offsetY: 0,
                                                                                  panDegree: 0,
                                                                                  w: 200,
                                                                                  h: 100))
        let pinch = GLStubPinchGestureRecognizer()

        program.tramsformController = transformController
        mode.program = program
        view.mode = mode
        gestureController.delegate = delegate
        gestureController.addGesture(to: view)
        gestureController.currentMode = mode

        pinch.stubLocation = CGPoint(x: 10, y: 10)
        pinch.stubState = .began
        gestureController.handlePinch(pinch)

        pinch.stubState = .changed
        pinch.stubNumberOfTouches = 2
        pinch.stubTouchLocations = [
            CGPoint(x: 20, y: 30),
            CGPoint(x: 60, y: 70)
        ]
        pinch.scale = 1.5
        gestureController.handlePinch(pinch)

        XCTAssertEqual(delegate.beginZoomingViews.count, 1)
        XCTAssertTrue(delegate.beginZoomingViews[0] === view)
        XCTAssertEqual(delegate.endZoomingScales, [0])
        XCTAssertEqual(transformController.updates.count, 1)
        XCTAssertEqual(transformController.updates[0].sx, 1.5, accuracy: 0.0001)
        XCTAssertEqual(transformController.updates[0].sy, 1.5, accuracy: 0.0001)
        XCTAssertEqual(pinch.scale, 1, accuracy: 0.0001)
    }

    func testRotateHandlerRotatesProgramWhenTouchBeginsInsideProgram() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let gestureController = IRGLGestureController()
        let delegate = RecordingGLViewDelegate()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000),
            parameter: nil
        )
        let transformController = RecordingTransformController()
        let rotation = GLStubRotationGestureRecognizer()

        program.tramsformController = transformController
        mode.program = program
        view.mode = mode
        gestureController.delegate = delegate
        gestureController.addGesture(to: view)
        gestureController.currentMode = mode

        rotation.stubLocation = CGPoint(x: 10, y: 10)
        rotation.stubState = .began
        gestureController.handleRotate(rotation)

        rotation.stubState = .changed
        rotation.rotation = 0.5
        gestureController.handleRotate(rotation)

        XCTAssertEqual(delegate.beginDraggingViews.count, 1)
        XCTAssertTrue(delegate.beginDraggingViews[0] === view)
        XCTAssertEqual(delegate.endDraggingWillDecelerate, [false])
        XCTAssertNil(delegate.endDraggingViews[0])
        XCTAssertEqual(transformController.rotations.count, 1)
        XCTAssertEqual(transformController.rotations[0], -0.5 * 180 / .pi, accuracy: 0.0001)
        XCTAssertEqual(rotation.rotation, 0, accuracy: 0.0001)
    }

    func testUpdateRotationDelegatesToCurrentProgramTransform() {
        let gestureController = IRGLGestureController()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D()
        let transformController = RecordingTransformController()

        program.tramsformController = transformController
        mode.program = program
        gestureController.currentMode = mode

        gestureController.updateRotation(.pi)

        XCTAssertEqual(transformController.rotations, [-180])
    }

    func testDoubleTapInsideProgramInstallsResetBlockFor2DTransform() {
        let gestureController = IRGLGestureController()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1, y: -1, width: 2, height: 2),
            parameter: nil
        )

        program.tramsformController = IRGLTransformController2D(viewportWidth: 2, viewportHeight: 2)
        mode.program = program
        gestureController.currentMode = mode

        gestureController.handleDoubleTap(UITapGestureRecognizer())

        XCTAssertNotNil(program.doResetToDefaultScaleBlock)
    }

    func testDoubleTapInsideProgramResetsZoomed2DTransformScale() {
        let gestureController = IRGLGestureController()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1, y: -1, width: 2, height: 2),
            parameter: nil
        )
        let transformController = IRGLTransformController2D(viewportWidth: 2, viewportHeight: 2)

        transformController.update(fx: 1, fy: 1, sx: 2, sy: 2)
        program.tramsformController = transformController
        mode.program = program
        gestureController.currentMode = mode

        XCTAssertEqual(program.getCurrentScale().x, 2, accuracy: 0.0001)
        XCTAssertEqual(program.getCurrentScale().y, 2, accuracy: 0.0001)

        gestureController.handleDoubleTap(UITapGestureRecognizer())

        XCTAssertEqual(program.getCurrentScale().x, 1, accuracy: 0.0001)
        XCTAssertEqual(program.getCurrentScale().y, 1, accuracy: 0.0001)
    }

    func testDoubleTapInsideProgramClearsResetBlockForNon2DTransform() {
        let gestureController = IRGLGestureController()
        let mode = IRGLRenderMode2D()
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: -1, y: -1, width: 2, height: 2),
            parameter: nil
        )

        program.tramsformController = RecordingTransformController()
        program.doResetToDefaultScaleBlock = { _ in true }
        mode.program = program
        gestureController.currentMode = mode

        gestureController.handleDoubleTap(UITapGestureRecognizer())

        XCTAssertNil(program.doResetToDefaultScaleBlock)
    }
}

private final class RecordingGLViewDelegate: NSObject, IRGLViewDelegate {
    private(set) var endDraggingViews: [IRGLView?] = []
    private(set) var endDraggingWillDecelerate: [Bool] = []
    private(set) var beginDraggingViews: [IRGLView?] = []
    private(set) var beginZoomingViews: [IRGLView?] = []
    private(set) var endZoomingScales: [CGFloat] = []

    func glViewDidEndDragging(_ view: IRGLView?, willDecelerate: Bool) {
        endDraggingViews.append(view)
        endDraggingWillDecelerate.append(willDecelerate)
    }

    func glViewWillBeginDragging(_ view: IRGLView?) {
        beginDraggingViews.append(view)
    }

    func glViewWillBeginZooming(_ view: IRGLView?) {
        beginZoomingViews.append(view)
    }

    func glViewDidEndDecelerating(_ view: IRGLView?) {}

    func glViewDidEndZooming(_ view: IRGLView?, atScale scale: CGFloat) {
        endZoomingScales.append(scale)
    }

    func glViewDidScroll(toBounds view: IRGLView?) {}
}

private final class GLStubPanGestureRecognizer: UIPanGestureRecognizer {
    var stubState: UIGestureRecognizer.State = .possible
    var stubLocation: CGPoint = .zero
    var stubTranslation: CGPoint = .zero
    var stubVelocity: CGPoint = .zero

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        stubLocation
    }

    override func translation(in view: UIView?) -> CGPoint {
        stubTranslation
    }

    override func setTranslation(_ translation: CGPoint, in view: UIView?) {
        stubTranslation = translation
    }

    override func velocity(in view: UIView?) -> CGPoint {
        stubVelocity
    }
}

private final class GLStubPinchGestureRecognizer: UIPinchGestureRecognizer {
    var stubState: UIGestureRecognizer.State = .possible
    var stubLocation: CGPoint = .zero
    var stubNumberOfTouches: Int = 0
    var stubTouchLocations: [CGPoint] = []

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override var numberOfTouches: Int {
        stubNumberOfTouches
    }

    override func location(in view: UIView?) -> CGPoint {
        stubLocation
    }

    override func location(ofTouch touchIndex: Int, in view: UIView?) -> CGPoint {
        stubTouchLocations[touchIndex]
    }
}

private final class GLStubRotationGestureRecognizer: UIRotationGestureRecognizer {
    var stubState: UIGestureRecognizer.State = .possible
    var stubLocation: CGPoint = .zero

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        stubLocation
    }
}

private final class RecordingTransformController: IRGLTransformController {
    private let scope: IRGLScope2D
    private(set) var rotations: [Float] = []
    private(set) var scrollOffsets: [(dx: Float, dy: Float)] = []
    private(set) var updates: [(fx: Float, fy: Float, sx: Float, sy: Float)] = []

    init(scope: IRGLScope2D = IRGLScope2D()) {
        self.scope = scope
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        scope
    }

    override func scroll(dx: Float, dy: Float) {
        scrollOffsets.append((dx, dy))
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        updates.append((fx, fy, sx, sy))
    }

    override func rotate(degree: Float) {
        rotations.append(degree)
    }
}
