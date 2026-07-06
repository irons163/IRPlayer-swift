import CoreGraphics
import XCTest
@testable import IRPlayer_swift

final class IRGLViewRenderStateTests: XCTestCase {

    func testResetClearsModeSpecificState() throws {
        let state = IRGLViewRenderState()
        let panoMode = makePanoMode()
        let fisheyeMode = makeFisheyeMode()

        state.configureFish2Pano(renderMode: panoMode)
        state.configureFisheye(renderMode: fisheyeMode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNotNil(state.fish2PanoParams)
        XCTAssertNotNil(state.fisheyeController)
        XCTAssertNotNil(state.fisheyeParameter)

        state.reset()

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertTrue(state.fish2PanoTextures.isEmpty)
        XCTAssertEqual(state.fish2PanoLastOutputSize, .zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
        XCTAssertNil(state.fisheyeMesh)
        XCTAssertNil(state.vrMesh)
        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeParameter)
        XCTAssertEqual(state.fisheyeLastSize, .zero)
        XCTAssertNil(state.distortionLeftMesh)
        XCTAssertNil(state.distortionRightMesh)
    }

    func testConfigureFish2PanoStoresProgramParams() throws {
        let state = IRGLViewRenderState()
        let mode = makePanoMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)

        state.configureFish2Pano(renderMode: mode)

        XCTAssertTrue(state.fish2PanoParams === params)
    }

    func testConfigureFish2PanoClearsStateForNonPanoMode() throws {
        let state = IRGLViewRenderState()
        state.configureFish2Pano(renderMode: makePanoMode())
        XCTAssertNotNil(state.fish2PanoParams)

        state.configureFish2Pano(renderMode: IRGLRenderMode2D())

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertTrue(state.fish2PanoTextures.isEmpty)
        XCTAssertEqual(state.fish2PanoLastOutputSize, .zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
    }

    func testConfigureFisheyeUsesProgramControllerAndParameter() throws {
        let state = IRGLViewRenderState()
        let mode = makeFisheyeMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram3DFisheye)
        let controller = try XCTUnwrap(program.tramsformController as? IRGLTransformController3DFisheye)
        let parameter = try XCTUnwrap(mode.parameter as? IRFisheyeParameter)

        state.configureFisheye(renderMode: mode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertTrue(state.fisheyeController === controller)
        XCTAssertTrue(state.fisheyeParameter === parameter)
    }

    func testConfigureFisheyeCreatesFallbackControllerAndDefaultParameter() {
        let state = IRGLViewRenderState()
        let mode = NilProgramFisheyeRenderMode()

        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)

        state.configureFisheye(renderMode: mode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNotNil(state.fisheyeController)
        XCTAssertEqual(state.fisheyeParameter?.width, 0)
        XCTAssertEqual(state.fisheyeParameter?.height, 0)
        XCTAssertEqual(state.fisheyeParameter?.latmax, 0)
    }

    func testConfigureFisheyeClearsStateForNonFisheyeMode() {
        let state = IRGLViewRenderState()
        state.configureFisheye(renderMode: makeFisheyeMode(),
                               viewportSize: CGSize(width: 320, height: 180))
        XCTAssertNotNil(state.fisheyeController)

        state.configureFisheye(renderMode: IRGLRenderMode2D(),
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeMesh)
        XCTAssertNil(state.fisheyeParameter)
        XCTAssertEqual(state.fisheyeLastSize, .zero)
    }

    private func makePanoMode() -> IRGLRenderMode2DFisheye2Pano {
        let mode = IRGLRenderMode2DFisheye2Pano()
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)
        return mode
    }

    private func makeFisheyeMode() -> IRGLRenderMode3DFisheye {
        let mode = IRGLRenderMode3DFisheye()
        let parameter = IRFisheyeParameter(width: 2,
                                           height: 2,
                                           up: false,
                                           rx: 1,
                                           ry: 1,
                                           cx: 1,
                                           cy: 1,
                                           latmax: 90)
        mode.parameter = parameter
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: parameter)
        return mode
    }
}

private final class NilProgramFisheyeRenderMode: IRGLRenderMode3DFisheye {
    override var programFactory: IRGLProgram2DFactory {
        NilProgramFactory()
    }
}

private final class NilProgramFactory: IRGLProgram2DFactory {
    override func createIRGLProgram(pixelFormat: IRPixelFormat,
                                    viewportRange: CGRect,
                                    parameter: IRMediaParameter?) -> IRGLProgram2D? {
        nil
    }
}
