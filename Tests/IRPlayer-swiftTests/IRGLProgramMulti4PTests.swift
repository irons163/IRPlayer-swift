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

    func testViewportRangesSplitMultiDisplayIntoQuadrants() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            displayMode: .multiDisplay,
            programCount: 4,
            selectedIndex: nil
        )

        XCTAssertEqual(ranges, expectedQuadrants())
    }

    func testViewportRangesShowOnlySelectedProgramInSingleDisplay() {
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

    func testViewportRangesHideAllProgramsForMissingSingleSelection() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            displayMode: .singleDisplay,
            programCount: 4,
            selectedIndex: nil
        )

        XCTAssertEqual(ranges, [.zero, .zero, .zero, .zero])
    }

    func testViewportRangesPreserveParentOrigin() {
        let ranges = IRGLProgramMulti4P.viewportRanges(
            in: CGRect(x: 10, y: 20, width: 400, height: 200),
            displayMode: .multiDisplay,
            programCount: 4,
            selectedIndex: nil
        )

        XCTAssertEqual(ranges, [
            CGRect(x: 10, y: 20, width: 200, height: 100),
            CGRect(x: 210, y: 20, width: 200, height: 100),
            CGRect(x: 10, y: 120, width: 200, height: 100),
            CGRect(x: 210, y: 120, width: 200, height: 100)
        ])
    }

    func testViewportRangesRejectMalformedGeometryAndEmptyPrograms() {
        XCTAssertEqual(
            IRGLProgramMulti4P.viewportRanges(
                in: CGRect(x: CGFloat.nan, y: 0, width: 400, height: 200),
                displayMode: .multiDisplay,
                programCount: 4,
                selectedIndex: nil
            ),
            []
        )
        XCTAssertEqual(
            IRGLProgramMulti4P.viewportRanges(
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: CGFloat.infinity
                ),
                displayMode: .multiDisplay,
                programCount: 4,
                selectedIndex: nil
            ),
            []
        )
        XCTAssertEqual(
            IRGLProgramMulti4P.viewportRanges(
                in: CGRect(x: 0, y: 0, width: 400, height: 200),
                displayMode: .multiDisplay,
                programCount: 0,
                selectedIndex: nil
            ),
            []
        )
        XCTAssertEqual(
            IRGLProgramMulti4P.viewportRanges(
                in: CGRect(x: 0, y: 0, width: 400, height: 200),
                displayMode: .multiDisplay,
                programCount: 5,
                selectedIndex: nil
            ),
            []
        )
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

    func testDoubleTapUsesResetBlockBeforeChangingDisplayMode() {
        let childPrograms = [
            RecordingMulti4PChild(touchResult: true, currentScale: CGPoint(x: 1, y: 1)),
            RecordingMulti4PChild(touchResult: false, currentScale: CGPoint(x: 1, y: 1))
        ]
        let program = IRGLProgramMulti4P(programs: childPrograms,
                                         viewprotRange: CGRect(x: 0, y: 0, width: 400, height: 200))
        var resetBlockCallCount = 0
        program.doResetToDefaultScaleBlock = { receivedProgram in
            resetBlockCallCount += 1
            XCTAssertTrue(receivedProgram === program)
            return true
        }
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 10, y: 10)))

        program.didDoubleTap()

        XCTAssertEqual(resetBlockCallCount, 1)
        XCTAssertEqual(childPrograms[0].recordedEvents, [.doubleTap])
        XCTAssertEqual(childPrograms[1].recordedEvents, [])
        XCTAssertEqual(program.displayMode, .multiDisplay)
    }

    func testDoubleTapResetsTouchedProgramWhenScaleIsNotDefault() {
        let childPrograms = [
            RecordingMulti4PChild(touchResult: false, currentScale: CGPoint(x: 1, y: 1)),
            RecordingMulti4PChild(touchResult: true, currentScale: CGPoint(x: 1, y: 1))
        ]
        childPrograms[1].tramsformController = FixedScaleTransformController(
            scopeScale: CGPoint(x: 2, y: 1),
            defaultScale: CGPoint(x: 1, y: 1)
        )
        let program = IRGLProgramMulti4P(programs: childPrograms,
                                         viewprotRange: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 10, y: 10)))

        program.didDoubleTap()

        XCTAssertEqual(childPrograms[0].recordedEvents, [])
        XCTAssertEqual(childPrograms[1].recordedEvents, [.doubleTap])
        XCTAssertEqual(program.displayMode, .multiDisplay)
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

    func testScalePinchAndRotateAreForwardedOnlyToTouchedProgram() {
        let childPrograms = [
            RecordingMulti4PChild(touchResult: false, currentScale: CGPoint(x: 1, y: 1)),
            RecordingMulti4PChild(touchResult: true, currentScale: CGPoint(x: 2, y: 3)),
            RecordingMulti4PChild(touchResult: false, currentScale: CGPoint(x: 4, y: 5)),
            RecordingMulti4PChild(touchResult: false, currentScale: CGPoint(x: 6, y: 7))
        ]
        let program = IRGLProgramMulti4P(programs: childPrograms,
                                         viewprotRange: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 10, y: 20)))

        program.setDefaultScale(1.75)
        let currentScale = program.getCurrentScale()
        program.didPinchByfx(260, fy: 90, dsx: 1.5, dsy: 2.0)
        program.didPinchByfx(265, fy: 95, sx: 8, sy: 9)
        program.didRotate(.pi / 3)

        XCTAssertEqual(currentScale, CGPoint(x: 2, y: 3))
        XCTAssertEqual(childPrograms[0].recordedEvents, [])
        XCTAssertEqual(childPrograms[2].recordedEvents, [])
        XCTAssertEqual(childPrograms[3].recordedEvents, [])
        XCTAssertEqual(childPrograms[1].recordedEvents, [
            .defaultScale(1.75),
            .pinch(fx: 260 - 200, fy: 90, sx: 1.5, sy: 2),
            .pinch(fx: 265 - 200, fy: 95, sx: 8, sy: 9),
            .rotate(.pi / 3)
        ])
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

private final class RecordingMulti4PChild: IRGLProgram2D {

    enum Event: Equatable {
        case defaultScale(Float)
        case pinch(fx: Float, fy: Float, sx: Float, sy: Float)
        case rotate(Float)
        case doubleTap
    }

    private let touchResult: Bool
    private let currentScale: CGPoint
    private(set) var recordedEvents: [Event] = []

    init(touchResult: Bool, currentScale: CGPoint) {
        self.touchResult = touchResult
        self.currentScale = currentScale
        super.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
    }

    override func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        touchResult
    }

    override func setDefaultScale(_ scale: Float) {
        recordedEvents.append(.defaultScale(scale))
    }

    override func getCurrentScale() -> CGPoint {
        currentScale
    }

    override func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        recordedEvents.append(.pinch(fx: fx, fy: fy, sx: sx, sy: sy))
    }

    override func didRotate(_ rotateRadians: Float) {
        recordedEvents.append(.rotate(rotateRadians))
    }

    override func didDoubleTap() {
        recordedEvents.append(.doubleTap)
    }
}

private final class FixedScaleTransformController: IRGLTransformController {

    private let scope: IRGLScope2D
    private let defaultScale: CGPoint

    init(scopeScale: CGPoint, defaultScale: CGPoint) {
        self.scope = IRGLScope2D(
            scaleX: Float(scopeScale.x),
            scaleY: Float(scopeScale.y),
            offsetX: 0,
            offsetY: 0,
            panDegree: 0,
            w: 400,
            h: 200
        )
        self.defaultScale = defaultScale
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        scope
    }

    override func getDefaultTransformScale() -> CGPoint {
        defaultScale
    }
}
