import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLProgramMultiTests: XCTestCase {

    func testContentModeViewportTextureAndFrameAreForwardedToChildren() {
        let children = [RecordingProgram2D(), RecordingProgram2D()]
        let program = IRGLProgramMulti(programs: children,
                                       viewprotRange: CGRect(x: 0, y: 0, width: 100, height: 50))
        let frame = IRFFVideoFrame()
        frame.width = 640
        frame.height = 360

        program.contentMode = .scaleAspectFill
        program.setViewportRange(CGRect(x: 10, y: 20, width: 300, height: 150), resetTransform: false)
        program.updateTextureWidth(640, height: 360)
        program.setRenderFrame(frame)

        XCTAssertEqual(children.map(\.contentMode), [.scaleAspectFill, .scaleAspectFill])
        XCTAssertEqual(children.map(\.viewportCalls.last), [
            .init(range: CGRect(x: 10, y: 20, width: 300, height: 150), resetTransform: false),
            .init(range: CGRect(x: 10, y: 20, width: 300, height: 150), resetTransform: false)
        ])
        XCTAssertEqual(children.map(\.textureUpdates.last), [
            .init(width: 640, height: 360),
            .init(width: 640, height: 360)
        ])
        XCTAssertTrue(children.allSatisfy { $0.renderedFrames.last === frame })
    }

    func testTouchAggregatesChildrenAndOutputSizeIsZero() {
        let miss = RecordingProgram2D(touchResult: false)
        let hit = RecordingProgram2D(touchResult: true)
        let program = IRGLProgramMulti(programs: [miss, hit],
                                       viewprotRange: CGRect(x: 0, y: 0, width: 100, height: 50))

        XCTAssertTrue(program.touchedInProgram(CGPoint(x: 500, y: 500)))
        XCTAssertEqual(miss.touchedPoints, [CGPoint(x: 500, y: 500)])
        XCTAssertEqual(hit.touchedPoints, [CGPoint(x: 500, y: 500)])
        XCTAssertEqual(program.getOutputSize(), .zero)
    }

    func testScalePanPinchAndDoubleTapAreForwardedToChildren() {
        let children = [RecordingProgram2D(), RecordingProgram2D()]
        let controllers = [
            RecordingTransformController(scopeScaleX: 2, scopeScaleY: 3),
            RecordingTransformController(scopeScaleX: 4, scopeScaleY: 5)
        ]
        for (child, controller) in zip(children, controllers) {
            child.tramsformController = controller
        }
        let program = IRGLProgramMulti(programs: children,
                                       viewprotRange: CGRect(x: 0, y: 0, width: 100, height: 50))

        program.setDefaultScale(1.5)
        program.didPanBydx(12, dy: -8)
        program.didPanByDegreeX(90, degreeY: -45)
        program.didPinchByfx(10, fy: 20, dsx: 1.5, dsy: 2)
        program.didPinchByfx(30, fy: 40, sx: 6, sy: 7)
        program.didDoubleTap()

        XCTAssertEqual(children.map(\.defaultScales), [[1.5], [1.5]])
        XCTAssertEqual(controllers.map(\.scrollDeltaCalls), [
            [.init(dx: 12, dy: -8)],
            [.init(dx: 12, dy: -8)]
        ])
        XCTAssertEqual(controllers.map(\.scrollDegreeCalls), [
            [.init(degreeX: 90, degreeY: -45)],
            [.init(degreeX: 90, degreeY: -45)]
        ])
        XCTAssertEqual(children.map(\.pinchCalls), [
            [
                .init(fx: 10, fy: 20, sx: 3, sy: 6),
                .init(fx: 30, fy: 40, sx: 6, sy: 7)
            ],
            [
                .init(fx: 10, fy: 20, sx: 6, sy: 10),
                .init(fx: 30, fy: 40, sx: 6, sy: 7)
            ]
        ])
        XCTAssertEqual(children.map(\.doubleTapCallCount), [1, 1])
    }
}

private final class RecordingProgram2D: IRGLProgram2D {
    struct ViewportCall: Equatable {
        let range: CGRect
        let resetTransform: Bool
    }

    struct TextureUpdate: Equatable {
        let width: Int
        let height: Int
    }

    struct PinchCall: Equatable {
        let fx: Float
        let fy: Float
        let sx: Float
        let sy: Float
    }

    private let touchResult: Bool
    private(set) var viewportCalls: [ViewportCall] = []
    private(set) var textureUpdates: [TextureUpdate] = []
    private(set) var renderedFrames: [IRFFVideoFrame] = []
    private(set) var defaultScales: [Float] = []
    private(set) var touchedPoints: [CGPoint] = []
    private(set) var pinchCalls: [PinchCall] = []
    private(set) var doubleTapCallCount = 0

    init(touchResult: Bool = false) {
        self.touchResult = touchResult
        super.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
    }

    override func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool = true) {
        viewportCalls.append(ViewportCall(range: viewportRange, resetTransform: resetTransform))
    }

    override func updateTextureWidth(_ w: Int, height h: Int) {
        textureUpdates.append(TextureUpdate(width: w, height: h))
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        renderedFrames.append(frame)
    }

    override func setDefaultScale(_ scale: Float) {
        defaultScales.append(scale)
    }

    override func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        touchedPoints.append(touchedPoint)
        return touchResult
    }

    override func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        pinchCalls.append(PinchCall(fx: fx, fy: fy, sx: sx, sy: sy))
    }

    override func didDoubleTap() {
        doubleTapCallCount += 1
    }
}

private final class RecordingTransformController: IRGLTransformController {
    struct ScrollDelta: Equatable {
        let dx: Float
        let dy: Float
    }

    struct ScrollDegree: Equatable {
        let degreeX: Float
        let degreeY: Float
    }

    private let scope: IRGLScope2D
    private(set) var scrollDeltaCalls: [ScrollDelta] = []
    private(set) var scrollDegreeCalls: [ScrollDegree] = []

    init(scopeScaleX: Float, scopeScaleY: Float) {
        scope = IRGLScope2D(scaleX: scopeScaleX,
                            scaleY: scopeScaleY,
                            offsetX: 0,
                            offsetY: 0,
                            panDegree: 0,
                            w: 0,
                            h: 0)
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        scope
    }

    override func scroll(dx: Float, dy: Float) {
        scrollDeltaCalls.append(ScrollDelta(dx: dx, dy: dy))
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        scrollDegreeCalls.append(ScrollDegree(degreeX: degreeX, degreeY: degreeY))
    }
}
