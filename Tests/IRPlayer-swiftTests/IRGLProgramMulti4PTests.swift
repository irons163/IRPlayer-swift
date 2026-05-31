//
//  IRGLProgramMulti4PTests.swift
//  IRPlayer-swiftTests
//
//  Created by Codex on 2026/5/24.
//

import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgramMulti4PTests: XCTestCase {

    func testViewportRangesPolicySplitsMultiDisplayIntoQuadrants() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            displayMode: .multiDisplay,
            programCount: 4,
            selectedIndex: nil
        )

        XCTAssertEqual(ranges, expectedQuadrants())
    }

    func testViewportRangesPolicyShowsOnlySelectedProgramInSingleDisplay() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            displayMode: .singleDisplay,
            programCount: 4,
            selectedIndex: 2
        )

        XCTAssertEqual(ranges, [
            .zero,
            .zero,
            CGRect(x: 0, y: 0, width: 400, height: 200),
            .zero
        ])
    }

    func testViewportRangesPolicyHidesAllProgramsForMissingSingleSelection() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            displayMode: .singleDisplay,
            programCount: 4,
            selectedIndex: nil
        )

        XCTAssertEqual(ranges, [.zero, .zero, .zero, .zero])
    }

    func testTouchSelectsProgramInMatchingQuadrant() {
        let program = makeProgram()

        let touched = program.touchedInProgram(CGPoint(x: 300, y: 150))

        XCTAssertTrue(touched)
        XCTAssertTrue(program.touchedProgram === program.programs[3])
    }

    func testTouchOutsideAllQuadrantsClearsTouchedProgram() {
        let program = makeProgram()
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 300, y: 150)))

        let touched = program.touchedInProgram(CGPoint(x: 401, y: 201))

        XCTAssertFalse(touched)
        XCTAssertNil(program.touchedProgram)
    }

    func testDoubleTapTogglesSelectedProgramBetweenSingleAndMultiDisplay() {
        let program = makeProgram()
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 300, y: 150)))

        program.didDoubleTap()

        XCTAssertEqual(program.displayMode, .singleDisplay)
        XCTAssertEqual(program.programs.map(\.viewprotRange), [
            .zero,
            .zero,
            .zero,
            CGRect(x: 0, y: 0, width: 400, height: 200)
        ])

        program.didDoubleTap()

        XCTAssertEqual(program.displayMode, .multiDisplay)
        XCTAssertEqual(program.programs.map(\.viewprotRange), expectedQuadrants())
    }

    func testPanAndPinchAreForwardedOnlyToTouchedProgram() {
        let childPrograms = (0..<4).map { _ in makeChildProgram() }
        let controllers: [RecordingTransformController] = childPrograms.map { _ in
            let controller = RecordingTransformController()
            controller.resetViewport(width: 400, height: 200, resetTransform: false)
            return controller
        }
        for (program, controller) in zip(childPrograms, controllers) {
            program.tramsformController = controller
        }
        let program = IRGLProgramMulti4P(programs: childPrograms, viewprotRange: CGRect(x: 0, y: 0, width: 400, height: 200))
        controllers.forEach { $0.removeAllEvents() }
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 300, y: 150)))

        program.didPanBydx(12, dy: -8)
        program.didPanByDegreeX(90, degreeY: -45)
        program.didPinchByfx(310, fy: 150, dsx: 1.5, dsy: 2.0)

        XCTAssertEqual(controllers[0].events, [])
        XCTAssertEqual(controllers[1].events, [])
        XCTAssertEqual(controllers[2].events, [])
        XCTAssertEqual(controllers[3].events, [
            .scrollDelta(dx: 12, dy: -8),
            .pinch(fx: 200 - 110 * Float(UIScreen.main.scale),
                   fy: 50 * Float(UIScreen.main.scale),
                   sx: 1.5,
                   sy: 2.0)
        ])

        program.didDoubleTap()
        program.didPanByDegreeX(90, degreeY: -45)

        XCTAssertEqual(controllers[3].events.last, .scrollDegree(degreeX: 90, degreeY: -45))
    }

    private func makeProgram() -> IRGLProgramMulti4P {
        IRGLProgramFactory.createIRGLProgram2DFisheye2Persp4P(pixelFormat: .RGB_IRPixelFormat,
                                                              viewportRange: CGRect(x: 0, y: 0, width: 400, height: 200),
                                                              parameter: nil)
    }

    private func makeChildProgram() -> IRGLProgram2D {
        IRGLProgram2D(pixelFormat: .RGB_IRPixelFormat,
                      viewportRange: .zero,
                      parameter: nil)
    }

    private func expectedQuadrants() -> [CGRect] {
        [
            CGRect(x: 0, y: 0, width: 200, height: 100),
            CGRect(x: 200, y: 0, width: 200, height: 100),
            CGRect(x: 0, y: 100, width: 200, height: 100),
            CGRect(x: 200, y: 100, width: 200, height: 100)
        ]
    }
}

private final class RecordingTransformController: IRGLTransformController2D {

    enum Event: Equatable {
        case scrollDelta(dx: Float, dy: Float)
        case scrollDegree(degreeX: Float, degreeY: Float)
        case pinch(fx: Float, fy: Float, sx: Float, sy: Float)
    }

    private(set) var events: [Event] = []

    override func scroll(dx: Float, dy: Float) {
        events.append(.scrollDelta(dx: dx, dy: dy))
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        events.append(.scrollDegree(degreeX: degreeX, degreeY: degreeY))
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        events.append(.pinch(fx: fx, fy: fy, sx: sx, sy: sy))
    }

    func removeAllEvents() {
        events.removeAll()
    }
}
