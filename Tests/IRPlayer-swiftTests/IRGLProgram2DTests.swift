import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

final class IRGLProgram2DTests: XCTestCase {

    func testTouchedInProgramUsesViewportRange() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )

        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 60, y: 40)))
        XCTAssertFalse(program.touchedInProgram(CGPoint(x: 9, y: 40)))
        XCTAssertFalse(program.touchedInProgram(CGPoint(x: 60, y: 101)))
    }

    func testOutputSizeFollowsShaderParams() {
        let program = IRGLProgram2D()

        program.shaderParams2D?.updateTextureWidth(640, height: 360)

        XCTAssertEqual(program.getOutputSize(), CGSize(width: 640, height: 360))
    }

    func testOutputSizeDefaultsToZeroWhenShaderParamsAreMissing() {
        let program = IRGLProgram2D()

        program.shaderParams2D = nil

        XCTAssertEqual(program.getOutputSize(), .zero)
    }

    func testCalculateViewportReturnsZeroWithoutTransformController() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )

        XCTAssertEqual(program.calculateViewport(), .zero)
    }

    func testCalculateViewportOffsetsShrunkenTransformInsideViewport() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )
        program.tramsformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 0.5,
                                                                                      scaleY: 0.25,
                                                                                      offsetX: 0,
                                                                                      offsetY: 0,
                                                                                      panDegree: 0,
                                                                                      w: 200,
                                                                                      h: 100))

        let viewport = program.calculateViewport()

        XCTAssertEqual(viewport.origin.x, -40, accuracy: 0.0001)
        XCTAssertEqual(viewport.origin.y, -17.5, accuracy: 0.0001)
        XCTAssertEqual(viewport.size.width, 100, accuracy: 0.0001)
        XCTAssertEqual(viewport.size.height, 80, accuracy: 0.0001)
    }

    func testCalculateViewportKeepsOriginForFullScaleTransform() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )
        program.tramsformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 1.25,
                                                                                      scaleY: 1,
                                                                                      offsetX: 0,
                                                                                      offsetY: 0,
                                                                                      panDegree: 0,
                                                                                      w: 200,
                                                                                      h: 100))

        XCTAssertEqual(program.calculateViewport(), CGRect(x: 10, y: 20, width: 100, height: 80))
    }

    func testCalculateViewportRejectsDerivedOverflow() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )
        program.tramsformController = RecordingTransformController(
            scope: IRGLScope2D(
                scaleX: .greatestFiniteMagnitude,
                scaleY: 1,
                offsetX: 0,
                offsetY: 0,
                panDegree: 0,
                w: 2,
                h: 100
            )
        )

        XCTAssertEqual(program.calculateViewport(), .zero)
    }

    func testViewportSizeRejectsNonFiniteOrOverflowingDimensions() {
        XCTAssertNil(IRGLProgram2D.viewportSize(from: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)))
        XCTAssertNil(IRGLProgram2D.viewportSize(from: CGRect(x: 0, y: 0, width: 10, height: CGFloat.infinity)))
        XCTAssertNil(IRGLProgram2D.viewportSize(from: CGRect(x: 0, y: 0, width: CGFloat(Int.max) * 2, height: 10)))
        XCTAssertNil(IRGLProgram2D.viewportSize(from: CGRect(x: 0, y: 0, width: 10, height: CGFloat(Int.max) * 2)))
    }

    func testViewportSizeConvertsFiniteNonNegativeDimensions() {
        let size = IRGLProgram2D.viewportSize(from: CGRect(x: 0, y: 0, width: 320.9, height: 180.2))

        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 180)
    }

    func testScrollToBoundsMapsHorizontalVerticalAndCombinedStatuses() {
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxX]), .horizontal)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinX]), .horizontal)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxY]), .vertical)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinY]), .vertical)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxX, .toMinY]), .both)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinX, .toMaxY]), .both)
    }

    func testScrollToBoundsIgnoresNonBoundsStatuses() {
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: []), .none)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.fail]), .none)
    }

    func testOutputScaleDecisionMapsAspectFitAndFill() throws {
        let fit = try XCTUnwrap(IRGLProgram2D.outputScaleDecision(
            outputWidth: 400,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFit,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))
        XCTAssertEqual(fit.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(fit.scaleY, 0.5, accuracy: 0.0001)
        XCTAssertTrue(fit.shouldUpdateToDefault)

        let fill = try XCTUnwrap(IRGLProgram2D.outputScaleDecision(
            outputWidth: 400,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFill,
            shouldUpdateToDefaultWhenOutputSizeChanged: false
        ))
        XCTAssertEqual(fill.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(fill.scaleY, 1, accuracy: 0.0001)
        XCTAssertFalse(fill.shouldUpdateToDefault)
    }

    func testOutputScaleDecisionRejectsInvalidOrUnscaledInputs() {
        XCTAssertNil(IRGLProgram2D.outputScaleDecision(
            outputWidth: 0,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFit,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))
        XCTAssertNil(IRGLProgram2D.outputScaleDecision(
            outputWidth: 400,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleToFill,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))
    }

    func testOutputScaleDecisionSkipsDefaultUpdateWhenOutputMatchesViewportScale() throws {
        let decision = try XCTUnwrap(IRGLProgram2D.outputScaleDecision(
            outputWidth: 100,
            outputHeight: 100,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFit,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))

        XCTAssertEqual(decision.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(decision.scaleY, 1, accuracy: 0.0001)
        XCTAssertFalse(decision.shouldUpdateToDefault)
    }

    func testSetViewportRangeIgnoresInvalidDimensionsWhenResettingTransform() {
        let program = IRGLProgram2D()
        let transformController = IRGLTransformController2D(viewportWidth: 320, viewportHeight: 180)
        program.tramsformController = transformController

        program.setViewportRange(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 180))

        XCTAssertEqual(transformController.getScope().w, 320)
        XCTAssertEqual(transformController.getScope().h, 180)
    }

    func testDidScrollNotifiesDelegateForBoundsStatuses() {
        let program = IRGLProgram2D()
        let delegate = ProgramDelegateSpy()
        program.delegate = delegate
        let transformController = IRGLTransformController()

        program.didScroll(status: [.toMaxX], transformController: transformController)
        program.didScroll(status: [.toMinY], transformController: transformController)
        program.didScroll(status: [.toMaxX, .toMinY], transformController: transformController)
        program.didScroll(status: [.fail], transformController: transformController)

        XCTAssertEqual(delegate.bounds, [.horizontal, .vertical, .both])
        XCTAssertTrue(delegate.programs.allSatisfy { $0 === program })
    }

    func testOutputSizeUpdateIgnoresZeroDimensionsWhenScalingTransform() {
        let program = IRGLProgram2D()
        let transformController = IRGLTransformController2D(viewportWidth: 320, viewportHeight: 180)
        program.tramsformController = transformController

        program.didUpdateOutputWH(0, 0)

        let defaultScale = transformController.getDefaultTransformScale()
        XCTAssertTrue(defaultScale.x.isFinite)
        XCTAssertTrue(defaultScale.y.isFinite)
        XCTAssertEqual(defaultScale.x, 1, accuracy: 0.0001)
        XCTAssertEqual(defaultScale.y, 1, accuracy: 0.0001)
    }

    func testOutputSizeUpdateScalesTransformAndUpdatesToDefault() {
        let program = IRGLProgram2D()
        let transformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 1,
                                                                                  scaleY: 1,
                                                                                  offsetX: 0,
                                                                                  offsetY: 0,
                                                                                  panDegree: 0,
                                                                                  w: 100,
                                                                                  h: 100))
        program.tramsformController = transformController

        program.didUpdateOutputWH(400, 200)

        let defaultScale = transformController.getDefaultTransformScale()
        XCTAssertEqual(defaultScale.x, 1, accuracy: 0.0001)
        XCTAssertEqual(defaultScale.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transformController.updateToDefaultCallCount, 1)
    }

    func testOutputSizeUpdateCanSkipDefaultTransformUpdate() {
        let program = IRGLProgram2D()
        let transformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 1,
                                                                                  scaleY: 1,
                                                                                  offsetX: 0,
                                                                                  offsetY: 0,
                                                                                  panDegree: 0,
                                                                                  w: 100,
                                                                                  h: 100))
        program.tramsformController = transformController

        program.didUpdateOutputWH(100, 100)

        let defaultScale = transformController.getDefaultTransformScale()
        XCTAssertEqual(defaultScale.x, 1, accuracy: 0.0001)
        XCTAssertEqual(defaultScale.y, 1, accuracy: 0.0001)
        XCTAssertEqual(transformController.updateToDefaultCallCount, 0)
    }

    func testGestureMethodsForwardToTransformController() {
        let program = IRGLProgram2D()
        let transformController = RecordingTransformController(scope: IRGLScope2D(scaleX: 2,
                                                                                  scaleY: 3,
                                                                                  offsetX: 0,
                                                                                  offsetY: 0,
                                                                                  panDegree: 0,
                                                                                  w: 200,
                                                                                  h: 100))
        program.tramsformController = transformController

        program.didPanBydx(4, dy: 5)
        program.didPanByDegreeX(6, degreeY: 7)
        program.didPinchByfx(10, fy: 20, sx: 2.5, sy: 3.5)
        program.didPinchByfx(30, fy: 40, dsx: 1.5, dsy: 2)
        program.didRotate(.pi / 2)

        XCTAssertEqual(transformController.scrollCalls, [CGPoint(x: 4, y: 5)])
        XCTAssertEqual(transformController.degreeScrollCalls, [CGPoint(x: 6, y: 7)])
        XCTAssertEqual(transformController.updateCalls.count, 2)
        XCTAssertEqual(transformController.updateCalls[0].sx, 2.5, accuracy: 0.0001)
        XCTAssertEqual(transformController.updateCalls[0].sy, 3.5, accuracy: 0.0001)
        XCTAssertEqual(transformController.updateCalls[1].sx, 3, accuracy: 0.0001)
        XCTAssertEqual(transformController.updateCalls[1].sy, 6, accuracy: 0.0001)
        XCTAssertEqual(transformController.rotateCalls, [90])
    }

    func testDoubleTapUsesCustomResetBeforeDefaultReset() {
        let program = IRGLProgram2D()
        let transformController = RecordingTransformController()
        program.tramsformController = transformController
        var blockCallCount = 0

        program.doResetToDefaultScaleBlock = { receivedProgram in
            blockCallCount += 1
            XCTAssertTrue(receivedProgram === program)
            return true
        }
        program.didDoubleTap()

        XCTAssertEqual(blockCallCount, 1)
        XCTAssertEqual(transformController.updateToDefaultCallCount, 0)

        program.doResetToDefaultScaleBlock = { _ in false }
        program.didDoubleTap()

        XCTAssertEqual(transformController.updateToDefaultCallCount, 1)
    }

    func testSetRenderFrameUpdatesTextureOnlyWhenSizeChanges() {
        let program = IRGLProgram2D()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 320, height: 180)
        )

        program.setRenderFrame(frame)
        XCTAssertEqual(program.shaderParams2D?.textureWidth, 320)
        XCTAssertEqual(program.shaderParams2D?.textureHeight, 180)

        program.shouldUpdateToDefaultWhenOutputSizeChanged = false
        program.setRenderFrame(frame)
        XCTAssertFalse(program.shouldUpdateToDefaultWhenOutputSizeChanged)
    }

    func testSetRenderFrameIgnoresMissingShaderParams() {
        let program = IRGLProgram2D()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 320, height: 180)
        )

        program.shaderParams2D = nil
        program.setRenderFrame(frame)

        XCTAssertNil(program.shaderParams2D)
    }
}

private final class ProgramDelegateSpy: IRGLProgramDelegate {
    private(set) var bounds: [IRGLTransformController.ScrollToBounds] = []
    private(set) var programs: [IRGLProgram2D] = []

    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D) {
        self.bounds.append(bounds)
        programs.append(program)
    }
}

private final class RecordingTransformController: IRGLTransformController {
    private let scope: IRGLScope2D
    private(set) var scrollCalls: [CGPoint] = []
    private(set) var degreeScrollCalls: [CGPoint] = []
    private(set) var updateCalls: [(fx: Float, fy: Float, sx: Float, sy: Float)] = []
    private(set) var rotateCalls: [Float] = []
    private(set) var updateToDefaultCallCount = 0

    init(scope: IRGLScope2D = IRGLScope2D(scaleX: 1,
                                          scaleY: 1,
                                          offsetX: 0,
                                          offsetY: 0,
                                          panDegree: 0,
                                          w: 320,
                                          h: 180)) {
        self.scope = scope
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        return scope
    }

    override func scroll(dx: Float, dy: Float) {
        scrollCalls.append(CGPoint(x: CGFloat(dx), y: CGFloat(dy)))
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        degreeScrollCalls.append(CGPoint(x: CGFloat(degreeX), y: CGFloat(degreeY)))
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        updateCalls.append((fx: fx, fy: fy, sx: sx, sy: sy))
    }

    override func rotate(degree: Float) {
        rotateCalls.append(degree)
    }

    override func updateToDefault() {
        updateToDefaultCallCount += 1
    }
}
