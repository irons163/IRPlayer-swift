import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgramVRTests: XCTestCase {

    func testDoubleTapRestoresInitialDefaultScaleForFisheyeController() {
        let controller = RecordingFisheyeTransformController(viewportWidth: 320,
                                                             viewportHeight: 180,
                                                             tileType: .up)
        let program = IRGLProgramVR(pixelFormat: .RGB_IRPixelFormat,
                                    viewportRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                                    parameter: nil)
        program.tramsformController = controller

        program.setDefaultScale(2)
        program.setDefaultScale(3)
        controller.recordedUpdates.removeAll()
        program.didDoubleTap()

        XCTAssertEqual(controller.recordedUpdates, [
            .init(fx: 0, fy: 0, sx: 2, sy: 2)
        ])
    }

    func testDoubleTapFallsBackToDefaultUpdateWithoutInitialScale() {
        let controller = RecordingDefaultTransformController()
        let program = IRGLProgramVR()
        program.tramsformController = controller

        program.didDoubleTap()

        XCTAssertEqual(controller.updateToDefaultCallCount, 1)
    }

    func testVerticalScrollRejectsVerticalBoundsOnly() {
        let program = IRGLProgramVR()
        let controller = IRGLTransformController()

        XCTAssertFalse(program.doScrollVertical(status: [.toMaxY], transformController: controller))
        XCTAssertFalse(program.doScrollVertical(status: [.toMinY], transformController: controller))
        XCTAssertTrue(program.doScrollVertical(status: [.toMaxX], transformController: controller))
        XCTAssertTrue(program.doScrollVertical(status: [], transformController: controller))
    }
}

private final class RecordingFisheyeTransformController: IRGLTransformController3DFisheye {
    struct Update: Equatable {
        let fx: Float
        let fy: Float
        let sx: Float
        let sy: Float
    }

    var recordedUpdates: [Update] = []

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        recordedUpdates.append(Update(fx: fx, fy: fy, sx: sx, sy: sy))
    }
}

private final class RecordingDefaultTransformController: IRGLTransformController {
    private(set) var updateToDefaultCallCount = 0

    override func updateToDefault() {
        updateToDefaultCallCount += 1
    }
}
