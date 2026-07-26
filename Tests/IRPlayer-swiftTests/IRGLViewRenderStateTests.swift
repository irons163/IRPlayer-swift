import CoreGraphics
import Metal
import QuartzCore
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
        XCTAssertNil(state.fish2PanoTextureCacheKey)
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

    func testConfigureFish2PanoRequestsLookupAgainAfterReset()
        throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let state = IRGLViewRenderState()
        let mode = makePanoMode()
        let program = try XCTUnwrap(
            mode.program as? IRGLProgram2DFisheye2Pano
        )
        let params = try XCTUnwrap(
            program.metalFish2PanoParams
        )

        state.configureFish2Pano(renderMode: mode)
        params.updateTextureWidth(16, height: 12)
        let firstPixelMap = try waitForPublishedPixelMap(
            in: params
        )
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(
                    width: Int(params.outputWidth),
                    height: Int(params.outputHeight)
                ),
                antialias: Int(params.antialias)
            )
        )
        XCTAssertNil(params.pixelMapIfReady())

        state.reset()
        state.configureFish2Pano(renderMode: mode)

        let replacementPixelMap =
            try waitForPublishedPixelMap(in: params)
        XCTAssertGreaterThan(
            replacementPixelMap.requestGeneration,
            firstPixelMap.requestGeneration
        )
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(
                    width: Int(params.outputWidth),
                    height: Int(params.outputHeight)
                ),
                antialias: Int(params.antialias)
            )
        )
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
        params.textureWidth = 4
        params.textureHeight = 2
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
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .waitingForTextures
        )

        XCTAssertEqual(params.acknowledgedCount, 2)
        XCTAssertNil(params.pixelMapIfReady())
        XCTAssertEqual(state.fish2PanoTextures.count, installedTextures.count)
        XCTAssertTrue(zip(state.fish2PanoTextures, installedTextures).allSatisfy {
            ($0 as AnyObject) === ($1 as AnyObject)
        })
    }

    func testPrepareFish2PanoTexturesRetriesPixelMapAfterUploadFailure()
        throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        var uploadAttemptCount = 0
        let state = IRGLViewRenderState(
            fish2PanoTextureUpload: {
                device,
                width,
                height,
                data in
                uploadAttemptCount += 1
                guard uploadAttemptCount > 1 else {
                    return nil
                }
                return IRGLViewRenderState
                    .makeTexUVTexture(
                        device: device,
                        width: width,
                        height: height,
                        data: data
                    )
            }
        )
        let params = StubFish2PanoShaderParams(
            elementCapacity: 2 * 2 * 2
        )
        params.outputWidth = 2
        params.outputHeight = 2
        params.antialias = 1
        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        let mode = InjectedPanoRenderMode(
            program: StubFish2PanoProgram(
                params: params
            )
        )
        state.configureFish2Pano(renderMode: mode)

        XCTAssertEqual(
            state.prepareFish2PanoTextures(
                device: device
            ),
            .waitingForTextures
        )
        XCTAssertNotNil(params.pixelMapIfReady())
        XCTAssertEqual(params.acknowledgedCount, 0)

        XCTAssertEqual(
            state.prepareFish2PanoTextures(
                device: device
            ),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        XCTAssertEqual(uploadAttemptCount, 2)
        XCTAssertEqual(params.acknowledgedCount, 1)
        XCTAssertNil(params.pixelMapIfReady())
    }

    func testPrepareFish2PanoTexturesKeepsCoherentCacheReadyWhileReplacementUploadRetries()
        throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        var failNextUpload = false
        let state = IRGLViewRenderState(
            fish2PanoTextureUpload: {
                device,
                width,
                height,
                data in
                if failNextUpload {
                    failNextUpload = false
                    return nil
                }
                return IRGLViewRenderState.makeTexUVTexture(
                    device: device,
                    width: width,
                    height: height,
                    data: data
                )
            }
        )
        let params = StubFish2PanoShaderParams(
            elementCapacity: 2 * 2 * 2
        )
        params.outputWidth = 2
        params.outputHeight = 2
        params.antialias = 1
        let mode = InjectedPanoRenderMode(
            program: StubFish2PanoProgram(
                params: params
            )
        )
        state.configureFish2Pano(renderMode: mode)
        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        let installedTextures = state.fish2PanoTextures
        XCTAssertEqual(params.acknowledgedCount, 1)

        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        failNextUpload = true

        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        XCTAssertEqual(params.acknowledgedCount, 1)
        XCTAssertNotNil(params.pixelMapIfReady())
        XCTAssertTrue(
            zip(
                state.fish2PanoTextures,
                installedTextures
            ).allSatisfy {
                ($0 as AnyObject) === ($1 as AnyObject)
            }
        )

        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        XCTAssertEqual(params.acknowledgedCount, 2)
        XCTAssertNil(params.pixelMapIfReady())
        XCTAssertFalse(
            zip(
                state.fish2PanoTextures,
                installedTextures
            ).allSatisfy {
                ($0 as AnyObject) === ($1 as AnyObject)
            }
        )
    }

    func testPrepareFish2PanoTexturesDoesNotReuseCacheForSameWidthDifferentHeight()
        throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        var failNextUpload = false
        let state = IRGLViewRenderState(
            fish2PanoTextureUpload: {
                device,
                width,
                height,
                data in
                if failNextUpload {
                    failNextUpload = false
                    return nil
                }
                return IRGLViewRenderState.makeTexUVTexture(
                    device: device,
                    width: width,
                    height: height,
                    data: data
                )
            }
        )
        let params = StubFish2PanoShaderParams(
            elementCapacity: 2 * 2 * 2
        )
        params.outputWidth = 2
        params.outputHeight = 2
        params.antialias = 1
        let mode = InjectedPanoRenderMode(
            program: StubFish2PanoProgram(
                params: params
            )
        )
        state.configureFish2Pano(renderMode: mode)
        params.textureWidth = 4
        params.textureHeight = 2
        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        let installedTextures = state.fish2PanoTextures
        XCTAssertEqual(
            state.fish2PanoTextureCacheKey?
                .inputTextureWidth,
            4
        )
        XCTAssertEqual(
            state.fish2PanoTextureCacheKey?
                .inputTextureHeight,
            2
        )

        params.textureHeight = 3

        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .waitingForTextures
        )
        XCTAssertTrue(
            zip(
                state.fish2PanoTextures,
                installedTextures
            ).allSatisfy {
                ($0 as AnyObject) === ($1 as AnyObject)
            }
        )

        params.queuePixelMap(
            outputWidth: 2,
            outputHeight: 2,
            antialias: 1
        )
        failNextUpload = true

        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .waitingForTextures
        )
        XCTAssertEqual(params.acknowledgedCount, 1)
        XCTAssertNotNil(params.pixelMapIfReady())
        XCTAssertTrue(
            zip(
                state.fish2PanoTextures,
                installedTextures
            ).allSatisfy {
                ($0 as AnyObject) === ($1 as AnyObject)
            }
        )

        XCTAssertEqual(
            state.prepareFish2PanoTextures(device: device),
            .ready(
                outputSize: CGSize(width: 2, height: 2),
                antialias: 1
            )
        )
        XCTAssertEqual(params.acknowledgedCount, 2)
        XCTAssertNil(params.pixelMapIfReady())
        XCTAssertEqual(
            state.fish2PanoTextureCacheKey?
                .inputTextureHeight,
            3
        )
        XCTAssertFalse(
            zip(
                state.fish2PanoTextures,
                installedTextures
            ).allSatisfy {
                ($0 as AnyObject) === ($1 as AnyObject)
            }
        )
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

    func testFisheyeMeshCacheRebuildsForSameSizeCalibrationChange()
        throws
    {
        let device = try makeMetalDevice()
        let drawable = try makeDrawable(device: device)
        let renderer = IRGLRenderYUV()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 8, height: 8)
        )
        let state = IRGLViewRenderState()
        let firstMode = makeFisheyeMode(
            parameter: IRFisheyeParameter(
                width: 8,
                height: 8,
                up: false,
                rx: 3,
                ry: 3,
                cx: 4,
                cy: 4,
                latmax: 80
            )
        )
        state.configureFisheye(
            renderMode: firstMode,
            viewportSize: CGSize(width: 8, height: 8)
        )
        _ = state.renderFisheyeIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let firstMesh = try XCTUnwrap(state.fisheyeMesh)
        _ = state.renderFisheyeIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        XCTAssertTrue(
            state.fisheyeMesh === firstMesh
        )

        let secondMode = makeFisheyeMode(
            parameter: IRFisheyeParameter(
                width: 8,
                height: 8,
                up: false,
                rx: 2,
                ry: 2,
                cx: 5,
                cy: 4,
                latmax: 80
            )
        )
        state.configureFisheye(
            renderMode: secondMode,
            viewportSize: CGSize(width: 8, height: 8)
        )
        _ = state.renderFisheyeIfNeeded(
            frame: frame,
            mode: secondMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let secondMesh = try XCTUnwrap(state.fisheyeMesh)

        XCTAssertFalse(firstMesh === secondMesh)
        XCTAssertEqual(
            state.fisheyeMeshCacheKey?.kind,
            .single
        )
        XCTAssertEqual(
            state.fisheyeMeshCacheKey?.centerX,
            5
        )
        XCTAssertEqual(
            state.fisheyeMeshCacheKey?.radiusY,
            2
        )
    }

    func testFisheyeMeshCacheDoesNotReuseMultiMeshForSingleMode()
        throws
    {
        let device = try makeMetalDevice()
        let drawable = try makeDrawable(device: device)
        let renderer = IRGLRenderYUV()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 8, height: 8)
        )
        let parameter = IRFisheyeParameter(
            width: 8,
            height: 8,
            up: false,
            rx: 3,
            ry: 3,
            cx: 4,
            cy: 4,
            latmax: 80
        )
        let multiMode = IRGLRenderModeMulti4P()
        multiMode.parameter = parameter
        multiMode.buildIRGLProgram(
            pixelFormat: .YUV_IRPixelFormat,
            viewprotRange: CGRect(
                x: 0,
                y: 0,
                width: 8,
                height: 8
            ),
            parameter: parameter
        )
        let state = IRGLViewRenderState()
        _ = state.renderMulti4PIfNeeded(
            frame: frame,
            mode: multiMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let multiMesh = try XCTUnwrap(state.fisheyeMesh)
        XCTAssertEqual(
            state.fisheyeMeshCacheKey?.kind,
            .multi4P
        )

        let singleMode = makeFisheyeMode(
            parameter: parameter
        )
        state.configureFisheye(
            renderMode: singleMode,
            viewportSize: CGSize(width: 8, height: 8)
        )
        _ = state.renderFisheyeIfNeeded(
            frame: frame,
            mode: singleMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let singleMesh = try XCTUnwrap(state.fisheyeMesh)

        XCTAssertFalse(multiMesh === singleMesh)
        XCTAssertEqual(
            state.fisheyeMeshCacheKey?.kind,
            .single
        )
    }

    func testVRMeshCacheReusesSameModeAndRebuildsForModeSwitch()
        throws
    {
        let device = try makeMetalDevice()
        let drawable = try makeDrawable(device: device)
        let renderer = IRGLRenderYUV()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 8, height: 8)
        )
        let state = IRGLViewRenderState()
        let firstMode = makeVRMode()
        let firstProgram = try XCTUnwrap(
            firstMode.program as? IRGLProgramVR
        )
        let firstProjection = try XCTUnwrap(
            firstProgram.mapProjection
                as? IRGLProjectionVR
        )

        _ = state.renderVRIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let firstMesh = try XCTUnwrap(state.vrMesh)
        XCTAssertEqual(
            state.vrMeshCacheKey?.modeIdentifier,
            ObjectIdentifier(firstMode)
        )
        XCTAssertEqual(
            state.vrMeshCacheKey?.projectionIdentifier,
            ObjectIdentifier(firstProjection)
        )
        XCTAssertEqual(
            state.vrMeshCacheKey?.projectionGeneration,
            firstProjection.meshSnapshot().generation
        )
        XCTAssertEqual(
            state.vrMeshCacheKey?.deviceIdentifier,
            ObjectIdentifier(device)
        )

        _ = state.renderVRIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        XCTAssertTrue(state.vrMesh === firstMesh)

        let secondMode = makeVRMode()
        let secondProgram = try XCTUnwrap(
            secondMode.program as? IRGLProgramVR
        )
        let secondProjection = try XCTUnwrap(
            secondProgram.mapProjection
                as? IRGLProjectionVR
        )
        XCTAssertFalse(firstProjection === secondProjection)

        _ = state.renderVRIfNeeded(
            frame: frame,
            mode: secondMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        let secondMesh = try XCTUnwrap(state.vrMesh)

        XCTAssertFalse(firstMesh === secondMesh)
        XCTAssertEqual(
            state.vrMeshCacheKey?.modeIdentifier,
            ObjectIdentifier(secondMode)
        )
        XCTAssertEqual(
            state.vrMeshCacheKey?.projectionIdentifier,
            ObjectIdentifier(secondProjection)
        )
    }

    func testConfigureVRAndResetClearStaleMeshCache()
        throws
    {
        let device = try makeMetalDevice()
        let drawable = try makeDrawable(device: device)
        let renderer = IRGLRenderYUV()
        let frame = IRFFVideoFrame()
        XCTAssertTrue(
            frame.setDimensions(width: 8, height: 8)
        )
        let state = IRGLViewRenderState()
        let firstMode = makeVRMode()
        _ = state.renderVRIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        XCTAssertNotNil(state.vrMesh)
        XCTAssertNotNil(state.vrMeshCacheKey)

        state.configureVR(renderMode: makeVRMode())

        XCTAssertNil(state.vrMesh)
        XCTAssertNil(state.vrMeshCacheKey)

        _ = state.renderVRIfNeeded(
            frame: frame,
            mode: firstMode,
            renderer: renderer,
            drawable: drawable,
            drawableSize: CGSize(width: 8, height: 8),
            device: device,
            completion: {}
        )
        XCTAssertNotNil(state.vrMesh)
        XCTAssertNotNil(state.vrMeshCacheKey)

        state.reset()

        XCTAssertNil(state.vrMesh)
        XCTAssertNil(state.vrMeshCacheKey)
    }

    private func makePanoMode() -> IRGLRenderMode2DFisheye2Pano {
        let mode = IRGLRenderMode2DFisheye2Pano()
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: nil)
        return mode
    }

    private func waitForPublishedPixelMap(
        in params: IRGLFish2PanoShaderParams,
        timeout: TimeInterval = 2
    ) throws -> IRGLFish2PanoPixelMapGeneration {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pixelMap = params.pixelMapIfReady() {
                return pixelMap
            }
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.005)
            )
        }
        return try XCTUnwrap(
            params.pixelMapIfReady(),
            "Timed out waiting for fish2pano lookup map"
        )
    }

    private func makeFisheyeMode(
        parameter: IRFisheyeParameter =
            IRFisheyeParameter(
                width: 2,
                height: 2,
                up: false,
                rx: 1,
                ry: 1,
                cx: 1,
                cy: 1,
                latmax: 90
            )
    ) -> IRGLRenderMode3DFisheye {
        let mode = IRGLRenderMode3DFisheye()
        mode.parameter = parameter
        mode.buildIRGLProgram(pixelFormat: .YUV_IRPixelFormat,
                              viewprotRange: CGRect(x: 0, y: 0, width: 320, height: 180),
                              parameter: parameter)
        return mode
    }

    private func makeVRMode() -> IRGLRenderModeVR {
        let mode = IRGLRenderModeVR()
        mode.buildIRGLProgram(
            pixelFormat: .YUV_IRPixelFormat,
            viewprotRange: CGRect(
                x: 0,
                y: 0,
                width: 8,
                height: 8
            ),
            parameter: nil
        )
        return mode
    }

    private func makeMetalDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice()
        else {
            throw XCTSkip("Metal device unavailable")
        }
        return device
    }

    private func makeDrawable(
        device: MTLDevice
    ) throws -> RenderStateTestMetalDrawable {
        let descriptor =
            MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 8,
                height: 8,
                mipmapped: false
            )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture =
                device.makeTexture(
                    descriptor: descriptor
                ) else {
            throw XCTSkip(
                "Offscreen Metal texture unavailable"
            )
        }
        return RenderStateTestMetalDrawable(
            texture: texture
        )
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
    private var requiredConfiguration:
        IRGLFish2PanoPixelMapConfigurationKey?
    private(set) var acknowledgedCount = 0

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
        let inputTextureWidth =
            max(Int(textureWidth), 1)
        let inputTextureHeight =
            max(Int(textureHeight), 1)
        if textureWidth <= 0 {
            textureWidth = GLint(inputTextureWidth)
        }
        if textureHeight <= 0 {
            textureHeight = GLint(inputTextureHeight)
        }
        let configuration =
            IRGLFish2PanoPixelMapConfigurationKey(
                inputTextureWidth: inputTextureWidth,
                inputTextureHeight:
                    inputTextureHeight,
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                antialias: antialias,
                fishAperture: fishaperture,
                fishCenterX: Int(fishcenterx),
                fishCenterY: Int(fishcentery),
                fishRadiusH: Int(fishradiush),
                latitudeStart: lat1,
                latitudeEnd: lat2,
                longitudeStart: long1,
                longitudeEnd: long2,
                transformX: transformX,
                transformY: transformY,
                transformZ: transformZ
            )
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
                    configurationKey:
                        configuration,
                    maps: maps
                ) else {
            return
        }
        requiredConfiguration = configuration
        queuedPixelMaps.append(pixelMap)
    }

    override func requiredPixelMapConfigurationKey()
        -> IRGLFish2PanoPixelMapConfigurationKey?
    {
        requiredConfiguration
    }

    override func pixelMapIfReady()
        -> IRGLFish2PanoPixelMapGeneration?
    {
        queuedPixelMaps.first
    }

    override func acknowledgePixelMap(
        _ pixelMap: IRGLFish2PanoPixelMapGeneration
    ) {
        guard queuedPixelMaps.first === pixelMap else {
            return
        }
        queuedPixelMaps.removeFirst()
        acknowledgedCount += 1
    }
}

private final class RenderStateTestMetalDrawable:
    NSObject,
    CAMetalDrawable
{
    let texture: MTLTexture
    let layer = CAMetalLayer()

    init(texture: MTLTexture) {
        self.texture = texture
        super.init()
    }

    func present() {}

    func present(
        at presentationTime: CFTimeInterval
    ) {}

    @objc func presentAfterMinimumDuration(
        _ duration: CFTimeInterval
    ) {}

    @objc func addPresentScheduledHandler(
        _ block: @escaping (MTLDrawable) -> Void
    ) {
        block(self)
    }

    @objc func addPresentedHandler(
        _ block: @escaping (MTLDrawable) -> Void
    ) {
        block(self)
    }
}
