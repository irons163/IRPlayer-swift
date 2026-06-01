import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgram2DTests: XCTestCase {

    func testStaticPolicyWrappersRemainSourceCompatible() throws {
        let viewportRange = CGRect(x: 0, y: 0, width: 320.9, height: 180.2)
        XCTAssertEqual(
            IRGLProgram2D.viewportSize(from: viewportRange)?.width,
            IRGLProgram2DPolicy.viewportSize(from: viewportRange)?.width
        )
        XCTAssertEqual(
            IRGLProgram2D.viewportSize(from: viewportRange)?.height,
            IRGLProgram2DPolicy.viewportSize(from: viewportRange)?.height
        )
        XCTAssertEqual(
            IRGLProgram2D.scrollToBounds(for: [.toMaxX, .toMinY]),
            IRGLProgram2DPolicy.scrollToBounds(for: [.toMaxX, .toMinY])
        )

        let wrapperDecision = try XCTUnwrap(IRGLProgram2D.outputScaleDecision(
            outputWidth: 400,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFit,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))
        let policyDecision = try XCTUnwrap(IRGLProgram2DPolicy.outputScaleDecision(
            outputWidth: 400,
            outputHeight: 200,
            viewportWidth: 100,
            viewportHeight: 100,
            contentMode: .scaleAspectFit,
            shouldUpdateToDefaultWhenOutputSizeChanged: true
        ))
        XCTAssertEqual(wrapperDecision.scaleX, policyDecision.scaleX, accuracy: 0.0001)
        XCTAssertEqual(wrapperDecision.scaleY, policyDecision.scaleY, accuracy: 0.0001)
        XCTAssertEqual(wrapperDecision.shouldUpdateToDefault, policyDecision.shouldUpdateToDefault)
    }

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

    func testCalculateViewportReturnsZeroWithoutTransformController() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
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

    func testScrollToBoundsPolicyMapsHorizontalVerticalAndCombinedStatuses() {
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxX]), .horizontal)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinX]), .horizontal)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxY]), .vertical)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinY]), .vertical)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMaxX, .toMinY]), .both)
        XCTAssertEqual(IRGLProgram2D.scrollToBounds(for: [.toMinX, .toMaxY]), .both)
    }

    func testScrollToBoundsPolicyIgnoresNonBoundsStatuses() {
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
}

private final class ProgramDelegateSpy: IRGLProgramDelegate {
    private(set) var bounds: [IRGLTransformController.ScrollToBounds] = []
    private(set) var programs: [IRGLProgram2D] = []

    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D) {
        self.bounds.append(bounds)
        programs.append(program)
    }
}
