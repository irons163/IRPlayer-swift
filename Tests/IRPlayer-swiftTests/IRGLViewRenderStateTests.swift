import CoreGraphics
import Metal
import XCTest
@testable import IRPlayer_swift

final class IRGLViewRenderStateTests: XCTestCase {

    func testResetClearsModeSpecificState() throws {
        let state = IRGLViewRenderState()
        let panoMode = makePanoMode()
        let fisheyeMode = makeFisheyeMode()
        let program = try XCTUnwrap(panoMode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 4
        params.outputHeight = 2
        params.antialias = 2

        state.configureFish2Pano(renderMode: panoMode)
        let readiness: IRGLViewRenderState.Fish2PanoTextureReadiness? =
            state.prepareFish2PanoTextures(device: nil as MTLDevice?)
        XCTAssertEqual(readiness, IRGLViewRenderState.Fish2PanoTextureReadiness.waitingForTextures)
        state.configureFisheye(renderMode: fisheyeMode,
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNotNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(state.fish2PanoLastAntialias, 2)
        XCTAssertNotNil(state.fisheyeController)
        XCTAssertNotNil(state.fisheyeParameter)

        state.reset()

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize.zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeParameter)
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
        let mode = makePanoMode()
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        params.outputWidth = 4
        params.outputHeight = 2
        params.antialias = 2

        state.configureFish2Pano(renderMode: mode)
        let readiness: IRGLViewRenderState.Fish2PanoTextureReadiness? =
            state.prepareFish2PanoTextures(device: nil as MTLDevice?)
        XCTAssertEqual(readiness, IRGLViewRenderState.Fish2PanoTextureReadiness.waitingForTextures)
        XCTAssertNotNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(state.fish2PanoLastAntialias, 2)

        state.configureFish2Pano(renderMode: IRGLRenderMode2D())

        XCTAssertNil(state.fish2PanoParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize.zero)
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

    func testConfigureFisheyeCreatesFallbackControllerAndDefaultParameter() throws {
        let state = IRGLViewRenderState()
        let mode = NilProgramFisheyeRenderMode()

        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)

        state.configureFisheye(renderMode: mode,
                               viewportSize: CGSize(width: 320, height: 180))

        let controller: IRGLTransformController3DFisheye = try XCTUnwrap(state.fisheyeController)
        let scope = controller.getScope()
        XCTAssertEqual(scope.w, 320)
        XCTAssertEqual(scope.h, 180)
        XCTAssertEqual(state.fisheyeParameter?.width, 0)
        XCTAssertEqual(state.fisheyeParameter?.height, 0)
        XCTAssertEqual(state.fisheyeParameter?.latmax, 0)
    }

    func testConfigureFisheyeClearsStateForNonFisheyeMode() {
        let state = IRGLViewRenderState()
        state.configureFisheye(renderMode: makeFisheyeMode(),
                               viewportSize: CGSize(width: 320, height: 180))
        XCTAssertNotNil(state.fisheyeController)
        XCTAssertNotNil(state.fisheyeParameter)

        state.configureFisheye(renderMode: IRGLRenderMode2D(),
                               viewportSize: CGSize(width: 320, height: 180))

        XCTAssertNil(state.fisheyeController)
        XCTAssertNil(state.fisheyeParameter)
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
