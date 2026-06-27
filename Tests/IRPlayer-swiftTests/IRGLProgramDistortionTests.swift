import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgramDistortionTests: XCTestCase {

    func testSetViewportRangeUsesHalfWidthForDistortionController() {
        let program = IRGLProgramDistortion(pixelFormat: .RGB_IRPixelFormat,
                                           viewportRange: CGRect(x: 0, y: 0, width: 100, height: 80),
                                           parameter: nil)
        let transformController = IRGLTransformControllerDistortion(viewportWidth: 100, viewportHeight: 80, tileType: .up)
        program.tramsformController = transformController

        program.setViewportRange(CGRect(x: 0, y: 0, width: 320, height: 180), resetTransform: true)

        XCTAssertEqual(transformController.getScope().w, 160)
        XCTAssertEqual(transformController.getScope().h, 180)
    }

    func testSetViewportRangeIgnoresInvalidDimensionsForDistortionController() {
        let program = IRGLProgramDistortion(pixelFormat: .RGB_IRPixelFormat,
                                           viewportRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                                           parameter: nil)
        let transformController = IRGLTransformControllerDistortion(viewportWidth: 160, viewportHeight: 180, tileType: .up)
        program.tramsformController = transformController

        program.setViewportRange(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 180), resetTransform: true)

        XCTAssertEqual(transformController.getScope().w, 160)
        XCTAssertEqual(transformController.getScope().h, 180)
    }

    func testTransformControllerDistortionReturnsOnlyDistortionControllers() {
        let program = IRGLProgramDistortion(pixelFormat: .RGB_IRPixelFormat,
                                           viewportRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                                           parameter: nil)

        program.tramsformController = IRGLTransformController2D(viewportWidth: 320, viewportHeight: 180)
        XCTAssertNil(program.transformControllerDistortion)

        let distortionController = IRGLTransformControllerDistortion(viewportWidth: 160, viewportHeight: 180, tileType: .up)
        program.tramsformController = distortionController
        XCTAssertTrue(program.transformControllerDistortion === distortionController)
    }

    func testVerticalScrollStopsAtDistortionBounds() {
        let program = IRGLProgramDistortion(pixelFormat: .RGB_IRPixelFormat,
                                           viewportRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                                           parameter: nil)
        let controller = IRGLTransformController()

        XCTAssertFalse(program.doScrollVertical(status: [.toMaxY], transformController: controller))
        XCTAssertFalse(program.doScrollVertical(status: [.toMinY], transformController: controller))
        XCTAssertTrue(program.doScrollVertical(status: [], transformController: controller))
    }
}
