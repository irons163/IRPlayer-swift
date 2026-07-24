import CoreGraphics
import Metal
import XCTest
#if SWIFT_PACKAGE
@testable import IRPlayerSwift
#else
@testable import IRPlayer_swift
#endif

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

    func testConfigureFish2PanoClearsCachedStateWhenParamsObjectChanges() throws {
        let state = IRGLViewRenderState()
        let firstMode = makePanoMode()
        let firstProgram = try XCTUnwrap(firstMode.program as? IRGLProgram2DFisheye2Pano)
        let firstParams = try XCTUnwrap(firstProgram.metalFish2PanoParams)
        firstParams.outputWidth = 4
        firstParams.outputHeight = 2
        firstParams.antialias = 2

        state.configureFish2Pano(renderMode: firstMode)
        let readiness = state.prepareFish2PanoTextures(device: nil as MTLDevice?)
        XCTAssertEqual(readiness, IRGLViewRenderState.Fish2PanoTextureReadiness.waitingForTextures)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(state.fish2PanoLastAntialias, 2)

        let secondMode = makePanoMode()
        let secondProgram = try XCTUnwrap(secondMode.program as? IRGLProgram2DFisheye2Pano)
        let secondParams = try XCTUnwrap(secondProgram.metalFish2PanoParams)
        secondParams.outputWidth = 4
        secondParams.outputHeight = 2
        secondParams.antialias = 2
        XCTAssertFalse(firstParams === secondParams)

        state.configureFish2Pano(renderMode: secondMode)

        XCTAssertTrue(state.fish2PanoParams === secondParams)
        XCTAssertEqual(state.fish2PanoLastOutputSize, CGSize.zero)
        XCTAssertEqual(state.fish2PanoLastAntialias, 0)
        XCTAssertTrue(state.fish2PanoTextures.isEmpty)
    }

    func testPrepareFish2PanoTexturesRejectsMismatchedGenerationWithoutReplacingCache() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let state = IRGLViewRenderState()
        let params = StubFish2PanoShaderParams(
            elementCapacity: 2 * 2 * 2
        )
        params.outputWidth = 2
        params.outputHeight = 2
        params.antialias = 2
        let mode = InjectedPanoRenderMode(program: StubFish2PanoProgram(params: params))

        state.configureFish2Pano(renderMode: mode)
        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 2
        )
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(outputSize: CGSize(width: 2, height: 2), antialias: 2)
        )
        let installedTextures = state.fish2PanoTextures
        XCTAssertEqual(installedTextures.count, 4)
        var uploadedValues = [Float](
            repeating: 0,
            count: 2 * 2 * 2
        )
        uploadedValues.withUnsafeMutableBytes {
            bytes in
            installedTextures[2].getBytes(
                bytes.baseAddress!,
                bytesPerRow:
                    2 * 2 * MemoryLayout<GLfloat>.stride,
                from: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0
            )
        }
        XCTAssertEqual(
            uploadedValues,
            [Float](repeating: 3, count: 8)
        )

        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        XCTAssertEqual(state.prepareFish2PanoTextures(device: device), .waitingForTextures)

        XCTAssertEqual(state.fish2PanoTextures.count, installedTextures.count)
        XCTAssertTrue(zip(state.fish2PanoTextures, installedTextures).allSatisfy {
            ($0 as AnyObject) === ($1 as AnyObject)
        })
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

    func testConfigureFisheyeFallbackAfterProgramControllerUsesCurrentViewport() throws {
        let state = IRGLViewRenderState()
        let programMode = makeFisheyeMode()
        state.configureFisheye(renderMode: programMode,
                               viewportSize: CGSize(width: 320, height: 180))
        let programController = try XCTUnwrap(state.fisheyeController)

        let fallbackMode = NilProgramFisheyeRenderMode()
        fallbackMode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                                      viewprotRange: CGRect(x: 0, y: 0, width: 90, height: 45),
                                      parameter: nil)
        state.configureFisheye(renderMode: fallbackMode,
                               viewportSize: CGSize(width: 90, height: 45))

        let fallbackController = try XCTUnwrap(state.fisheyeController)
        let scope = fallbackController.getScope()
        XCTAssertFalse(fallbackController === programController)
        XCTAssertEqual(scope.w, 90)
        XCTAssertEqual(scope.h, 45)
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

private final class InjectedPanoRenderMode: IRGLRenderMode2DFisheye2Pano {
    init(program: IRGLProgram2DFisheye2Pano) {
        super.init()
        self.program = program
    }
}

private final class StubFish2PanoProgram: IRGLProgram2DFisheye2Pano {
    private let params: IRGLFish2PanoShaderParams

    override var metalFish2PanoParams: IRGLFish2PanoShaderParams? {
        params
    }

    init(params: IRGLFish2PanoShaderParams) {
        self.params = params
        super.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
    }
}

private final class StubFish2PanoShaderParams: IRGLFish2PanoShaderParams {
    private let elementCapacity: Int
    private var requestGeneration = 0
    private var queuedPixelMaps:
        [IRGLFish2PanoPixelMapGeneration] = []

    init(elementCapacity: Int) {
        self.elementCapacity = elementCapacity
        super.init()
    }

    func queuePixelMap(
        outputWidth: Int,
        outputHeight: Int,
        antialias: Int
    ) {
        requestGeneration += 1
        let textureCount =
            IRGLFish2PanoPixelMapGeneration.textureCount(
                antialias: antialias
            ) ?? 0
        let maps = (0..<textureCount).map {
            index in
            Array<GLfloat>(
                repeating: GLfloat(index + 1),
                count: elementCapacity
            )
        }
        guard let pixelMap =
                IRGLFish2PanoPixelMapGeneration(
                    requestGeneration:
                        requestGeneration,
                    outputWidth: outputWidth,
                    outputHeight: outputHeight,
                    antialias: antialias,
                    maps: maps
                ) else {
            return
        }
        queuedPixelMaps.append(pixelMap)
    }

    override func takePixelMapIfReady()
        -> IRGLFish2PanoPixelMapGeneration?
    {
        guard !queuedPixelMaps.isEmpty else {
            return nil
        }
        return queuedPixelMaps.removeFirst()
    }
}
