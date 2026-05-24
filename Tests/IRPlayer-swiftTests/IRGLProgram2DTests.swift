import CoreGraphics
import XCTest
@testable import IRPlayer_swift

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

    func testCalculateViewportReturnsZeroWithoutTransformController() {
        let program = IRGLProgram2D(
            pixelFormat: .RGB_IRPixelFormat,
            viewportRange: CGRect(x: 10, y: 20, width: 100, height: 80),
            parameter: nil
        )

        XCTAssertEqual(program.calculateViewport(), .zero)
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
}

private final class ProgramDelegateSpy: IRGLProgramDelegate {
    private(set) var bounds: [IRGLTransformController.ScrollToBounds] = []
    private(set) var programs: [IRGLProgram2D] = []

    func didScrollToBounds(_ bounds: IRGLTransformController.ScrollToBounds, withProgram program: IRGLProgram2D) {
        self.bounds.append(bounds)
        programs.append(program)
    }
}
