import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgram3DFisheyeTests: XCTestCase {

    func testOutputSizeUpdateRefreshesAutoUpdatingParameterAndProjection() {
        let parameter = IRMediaParameter(width: 320, height: 180)
        let projection = RecordingProjection()
        let program = IRGLProgram3DFisheye(pixelFormat: .RGB_IRPixelFormat,
                                          viewportRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                                          parameter: parameter)
        program.mapProjection = projection

        program.didUpdateOutputWH(640, 360)

        XCTAssertEqual(parameter.width, 640)
        XCTAssertEqual(parameter.height, 360)
        XCTAssertTrue(projection.updatedParameter === parameter)
    }

    func testOutputSizeUpdateIgnoresDisabledAutoUpdateOrUnchangedSize() {
        let parameter = IRMediaParameter(width: 320, height: 180)
        let projection = RecordingProjection()
        let program = IRGLProgram3DFisheye(pixelFormat: .RGB_IRPixelFormat,
                                          viewportRange: .zero,
                                          parameter: parameter)
        program.mapProjection = projection

        program.didUpdateOutputWH(320, 180)
        XCTAssertNil(projection.updatedParameter)

        parameter.autoUpdate = false
        program.didUpdateOutputWH(640, 360)

        XCTAssertEqual(parameter.width, 320)
        XCTAssertEqual(parameter.height, 180)
        XCTAssertNil(projection.updatedParameter)
    }

    func testVerticalScrollRejectsVerticalBoundsOnly() {
        let program = IRGLProgram3DFisheye()
        let controller = IRGLTransformController()

        XCTAssertFalse(program.doScrollVertical(status: [.toMaxY], transformController: controller))
        XCTAssertFalse(program.doScrollVertical(status: [.toMinY], transformController: controller))
        XCTAssertTrue(program.doScrollVertical(status: [.toMaxX], transformController: controller))
        XCTAssertTrue(program.doScrollVertical(status: [], transformController: controller))
    }
}

private final class RecordingProjection: IRGLProjection {
    private(set) var updatedParameter: IRMediaParameter?

    func update(with parameter: IRMediaParameter) {
        updatedParameter = parameter
    }

    func updateVertex() {}
    func draw() {}
}
