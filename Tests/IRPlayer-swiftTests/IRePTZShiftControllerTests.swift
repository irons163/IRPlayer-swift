import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRePTZShiftControllerTests: XCTestCase {

    func testShiftDegreeDoesNothingWhenDisabled() {
        let controller = IRePTZShiftController()
        let program = PanRecordingProgram()
        controller.program = program
        controller.enabled = false
        controller.panAngle = 180
        controller.tiltAngle = 90

        controller.shiftDegreeX(45, degreeY: 15)

        XCTAssertTrue(program.panCalls.isEmpty)
    }

    func testShiftDegreeSendsZeroForAxesWithoutConfiguredAngles() {
        let controller = IRePTZShiftController()
        let program = PanRecordingProgram()
        controller.program = program

        controller.shiftDegreeX(45, degreeY: 15)

        XCTAssertEqual(program.panCalls.count, 1)
        XCTAssertEqual(program.panCalls[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(program.panCalls[0].y, 0, accuracy: 0.0001)
    }

    func testShiftDegreeScalesByAngleAndFactor() {
        let controller = IRePTZShiftController()
        let program = PanRecordingProgram()
        controller.program = program
        controller.panAngle = 180
        controller.tiltAngle = 90
        controller.panFactor = 0.5
        controller.tiltFactor = 2

        controller.shiftDegreeX(45, degreeY: -10)

        XCTAssertEqual(program.panCalls.count, 1)
        XCTAssertEqual(program.panCalls[0].x, 45, accuracy: 0.0001)
        XCTAssertEqual(program.panCalls[0].y, -80, accuracy: 0.0001)
    }

    func testShiftDegreeDefaultsNonFiniteConfigurationToZero() {
        let controller = IRePTZShiftController()
        let program = PanRecordingProgram()
        controller.program = program
        controller.panAngle = .nan
        controller.tiltAngle = 90
        controller.panFactor = 1
        controller.tiltFactor = .infinity

        controller.shiftDegreeX(45, degreeY: 15)

        XCTAssertEqual(program.panCalls.count, 1)
        XCTAssertEqual(program.panCalls[0].x, 0)
        XCTAssertEqual(program.panCalls[0].y, 0)
    }
}

private final class PanRecordingProgram: IRGLProgram2D {
    private(set) var panCalls: [(x: Float, y: Float)] = []

    override func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        panCalls.append((degreeX, degreeY))
    }
}
