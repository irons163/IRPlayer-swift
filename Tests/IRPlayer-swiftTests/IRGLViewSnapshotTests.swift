import CoreVideo
import Metal
import QuartzCore
import simd
import UIKit
import XCTest
@testable import IRPlayer_swift

final class IRGLViewSnapshotTests: XCTestCase {

    func testInitDoesNotPrintMetalSetupDebugOutput() {
        let output = captureStandardOutput {
            _ = IRGLView(frame: .zero)
        }

        XCTAssertEqual(output, "")
    }

    func testCreateImageFromFramebufferReturnsImageForZeroSizedView() {
        let view = IRGLView(frame: .zero)

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size, .zero)
    }

    func testPlayerInitializerStoresAbstractPlayerAndBuildsDefaultModes() {
        let player = IRPlayerImp.player()
        player.manager = nil

        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8), player: player)

        XCTAssertTrue(view.abstractPlayer === player)
        XCTAssertFalse(view.getRenderModes().isEmpty)
        XCTAssertNotNil(view.getCurrentRenderMode())
        withExtendedLifetime(player) {}
    }

    func testLayoutAndQueueHelpersRemainCallable() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        var didRunInQueue = false

        view.layoutSubviews()
        view.runSyncInQueue {
            didRunInQueue = true
        }
        view.clearCanvas()
        let snapshotView = IRGLView(frame: .zero)
        snapshotView.doSnapShot()

        XCTAssertTrue(didRunInQueue)
        XCTAssertTrue(snapshotView.willDoSnapshot)
        snapshotView.willDoSnapshot = false
    }

    func testInitGLCanReadMainThreadStateFromBackgroundQueue() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let finished = expectation(description: "background initGL finished")

        DispatchQueue.global(qos: .userInitiated).async {
            view.initGL(with: .NV12_IRPixelFormat)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 2)
        XCTAssertFalse(view.getRenderModes().isEmpty)
    }

    func testCreateImageFromFramebufferReturnsImageForNonZeroView() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))

        let image = view.createImageFromFramebuffer()

        XCTAssertEqual(image.size.width, 12, accuracy: 0.0001)
        XCTAssertEqual(image.size.height, 8, accuracy: 0.0001)
    }

    func testSendVideoFrameStoresCurrentFrameDimensions() {
        let view = IRGLView(frame: .zero)
        let frame = IRFFVideoFrame()
        frame.width = 123
        frame.height = 45

        view.send(videoFrame: frame)

        XCTAssertEqual(view.lastFrameWidth, 123)
        XCTAssertEqual(view.lastFrameHeight, 45)
    }

    func testRenderImageFallbackHandlesRGBCVAndUnsupportedFrames() throws {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let rgbFrame = IRVideoFrameRGB(linesize: 3, rgb: Data([0xff, 0, 0]))
        rgbFrame.width = 1
        rgbFrame.height = 1
        let cvFrame = IRFFCVYUVVideoFrame(pixelBuffer: try makePixelBuffer(width: 2, height: 3))
        let unsupportedFrame = IRFFVideoFrame()
        unsupportedFrame.width = 4
        unsupportedFrame.height = 5

        view.send(videoFrame: rgbFrame)
        XCTAssertEqual(view.lastFrameWidth, 1)
        XCTAssertEqual(view.lastFrameHeight, 1)

        view.send(videoFrame: cvFrame)
        XCTAssertEqual(view.lastFrameWidth, 2)
        XCTAssertEqual(view.lastFrameHeight, 3)

        view.send(videoFrame: unsupportedFrame)
        XCTAssertEqual(view.lastFrameWidth, 4)
        XCTAssertEqual(view.lastFrameHeight, 5)
    }

    func testRenderRoutesFrameThroughSelected2DRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderMode2D()
        let renderer = ViewRenderRecorder()
        let frame = makeRGBFrame()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: frame)

        XCTAssertEqual(renderer.renderCallCount, 1)
        XCTAssertTrue(renderer.lastFrame === frame)
    }

    func testRenderRoutesFlatMultiFrameThroughRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = ViewFlatMultiRenderMode()
        let renderer = ViewRenderRecorder()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: makeRGBFrame())

        XCTAssertEqual(renderer.renderMultiCallCount, 1)
        XCTAssertEqual(renderer.lastViewportCount, 4)
    }

    func testRenderRoutesMulti4PFisheyeFrameThroughRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderModeMulti4P()
        let renderer = ViewRenderRecorder()
        mode.parameter = makeFisheyeParameter()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: makeRGBFrame())

        XCTAssertEqual(renderer.renderFisheyeMultiCallCount, 1)
        XCTAssertEqual(renderer.lastMVPCount, 4)
        XCTAssertEqual(renderer.lastViewportCount, 4)
    }

    func testRenderRoutesDistortionFrameThroughRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderModeDistortion()
        let renderer = ViewRenderRecorder()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: makeRGBFrame())

        XCTAssertEqual(renderer.renderDistortionCallCount, 1)
    }

    func testRenderRoutesFisheyeFrameThroughRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderMode3DFisheye()
        let renderer = ViewRenderRecorder()
        mode.parameter = makeFisheyeParameter()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: makeRGBFrame())

        XCTAssertEqual(renderer.renderFisheyeCallCount, 1)
    }

    func testRenderRoutesVRFrameThroughRenderer() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderModeVR()
        let renderer = ViewRenderRecorder()
        view.setRenderModes([mode])
        mode.renderer = renderer

        view.send(videoFrame: makeRGBFrame())

        XCTAssertEqual(renderer.renderFisheyeCallCount, 1)
    }

    func testRenderClearsFish2PanoUntilLookupTexturesAreReady() throws {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderMode2DFisheye2Pano()
        let renderer = ViewRenderRecorder()
        view.setRenderModes([mode])
        mode.renderer = renderer
        let params = try XCTUnwrap((mode.program as? IRGLProgram2DFisheye2Pano)?.metalFish2PanoParams)
        params.outputWidth = 4
        params.outputHeight = 2
        params.antialias = 1

        view.send(videoFrame: IRFFVideoFrame())

        XCTAssertEqual(renderer.renderClearCallCount, 1)
        XCTAssertEqual(renderer.renderFish2PanoCallCount, 0)
    }

    func testRenderUploadsFish2PanoLookupTextureWhenPixelMapIsReady() throws {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 12, height: 8))
        let mode = IRGLRenderMode2DFisheye2Pano()
        let renderer = ViewRenderRecorder()
        view.setRenderModes([mode])
        mode.renderer = renderer
        let params = try XCTUnwrap((mode.program as? IRGLProgram2DFisheye2Pano)?.metalFish2PanoParams)
        let expectedOutputSize = try XCTUnwrap(
            IRGLFish2PanoShaderParams.outputSize(forTextureWidth: 64, height: 48)
        )

        view.send(videoFrame: makeRGBFrame(width: 64, height: 48))
        let deadline = Date().addingTimeInterval(2)
        var renderAttempts = 1
        while renderer.renderFish2PanoCallCount == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            view.render(nil)
            renderAttempts += 1
        }

        XCTAssertEqual(
            renderer.renderFish2PanoCallCount,
            1,
            "attempts=\(renderAttempts) clears=\(renderer.renderClearCallCount) texture=\(params.textureWidth)x\(params.textureHeight) output=\(params.outputWidth)x\(params.outputHeight)"
        )
        XCTAssertEqual(renderer.lastFish2PanoTextureCount, 1)
        XCTAssertEqual(renderer.lastFish2PanoOutputSize,
                       CGSize(width: expectedOutputSize.width, height: expectedOutputSize.height))
    }

    func testRendererCleanupBranchesRemainCallable() {
        let view = IRGLView(frame: .zero)

        view.rendererType = .empty
        view.cleanViewIgnore()
        view.rendererType = .AVPlayerLayer
        view.cleanViewIgnore()
        view.rendererType = .AVPlayerPixelBufferVR
        view.cleanViewIgnore()
        view.rendererType = .FFmpegPixelBuffer
        view.cleanViewIgnore()
        view.rendererType = .FFmpegPixelBufferVR
        view.cleanViewIgnore()

        XCTAssertEqual(view.rendererType, .FFmpegPixelBufferVR)
    }

    func testDegreeScrollDelegatesThroughCurrentProgram() {
        let view = IRGLView(frame: .zero)
        let mode = IRGLRenderMode2D()
        let transformController = ViewRecordingTransformController()

        view.setRenderModes([mode])
        _ = view.choose(renderMode: mode, withImmediatelyRenderOnce: false)
        mode.program?.tramsformController = transformController

        view.scroll(byDegreeX: 3, degreeY: -4)

        XCTAssertEqual(transformController.degreeScrolls.map { "\($0.x),\($0.y)" }, ["3.0,-4.0"])
    }

    func testReloadGravityModeMapsPlayerGravityToCurrentProgramContentMode() throws {
        let player = IRPlayerImp.player()
        player.manager = nil
        let view = IRGLView(frame: .zero, player: player)
        let mode = IRGLRenderMode2D()

        view.setRenderModes([mode])
        XCTAssertTrue(view.choose(renderMode: mode, withImmediatelyRenderOnce: false))
        _ = try XCTUnwrap(mode.program)

        let cases: [(IRGravityMode, IRGLRenderContentMode)] = [
            (.resizeAspect, .scaleAspectFit),
            (.resizeAspectFill, .scaleAspectFill),
            (.resize, .scaleToFill)
        ]

        for (gravity, expectedContentMode) in cases {
            player.viewGravityMode = gravity
            view.reloadGravityMode()

            XCTAssertEqual(mode.program?.contentMode, expectedContentMode)
        }

        withExtendedLifetime(player) {}
    }

    func testUpdateScopeUsesPanoControllerCenterAndScaledScope() throws {
        let view = IRGLView(frame: .zero)
        let mode = IRGLRenderMode2DFisheye2Pano()

        view.setRenderModes([mode])
        XCTAssertTrue(view.choose(renderMode: mode, withImmediatelyRenderOnce: false))
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let transformController = ViewRecordingTransformController(
            scope: IRGLScope2D(scaleX: 2,
                               scaleY: 3,
                               offsetX: 0,
                               offsetY: 0,
                               panDegree: 0,
                               w: 80,
                               h: 40)
        )
        program.tramsformController = transformController

        view.updateScope(byFx: 10, fy: 20, dsx: 1.5, dsy: 0.5)

        XCTAssertEqual(transformController.updates.map { "\($0.fx),\($0.fy),\($0.sx),\($0.sy)" }, ["40.0,20.0,3.0,1.5"])
    }

    func testScrollByDxWrapsPanoOffsetWithinOutputWidth() throws {
        let view = IRGLView(frame: .zero)
        let mode = IRGLRenderMode2DFisheye2Pano()

        view.setRenderModes([mode])
        XCTAssertTrue(view.choose(renderMode: mode, withImmediatelyRenderOnce: false))
        let program = try XCTUnwrap(mode.program as? IRGLProgram2DFisheye2Pano)
        let params = try XCTUnwrap(program.metalFish2PanoParams)
        let transformController = ViewRecordingTransformController(
            scope: IRGLScope2D(scaleX: 2,
                               scaleY: 1,
                               offsetX: 0,
                               offsetY: 0,
                               panDegree: 0,
                               w: 50,
                               h: 40)
        )
        params.outputWidth = 100
        params.offsetX = 0
        program.tramsformController = transformController

        view.scroll(byDx: 500, dy: 0)
        XCTAssertEqual(params.offsetX, -100, accuracy: 0.0001)

        view.scroll(byDx: -500, dy: 0)
        XCTAssertEqual(params.offsetX, 100, accuracy: 0.0001)
        XCTAssertEqual(transformController.linearScrolls.map { "\($0.dx),\($0.dy)" }, ["500.0,0.0", "-500.0,0.0"])
    }

    func testFisheyeModeWithoutProgramUsesFallbackControllerForGestures() {
        let view = IRGLView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        let mode = NilProgramFisheyeRenderMode()

        view.setRenderModes([mode])
        XCTAssertTrue(view.choose(renderMode: mode, withImmediatelyRenderOnce: false))
        XCTAssertNil(mode.program)

        view.updateScope(byFx: 10, fy: 20, dsx: 1.25, dsy: 1.5)
        view.scroll(byDx: 3, dy: -4)
        view.scroll(byDegreeX: 5, degreeY: -6)

        XCTAssertTrue(view.getCurrentRenderMode() === mode)
    }

    func testRenderModeSelectionRequiresRegisteredMode() {
        let view = IRGLView(frame: .zero)
        let firstMode = IRGLRenderMode2D()
        let secondMode = IRGLRenderMode2D()
        let externalMode = IRGLRenderMode2D()

        view.setRenderModes([firstMode, secondMode])

        XCTAssertEqual(view.getRenderModes().count, 2)
        XCTAssertTrue(view.getCurrentRenderMode() === firstMode)
        XCTAssertFalse(view.choose(renderMode: nil, withImmediatelyRenderOnce: false))
        XCTAssertFalse(view.choose(renderMode: externalMode, withImmediatelyRenderOnce: false))

        XCTAssertTrue(view.choose(renderMode: secondMode, withImmediatelyRenderOnce: false))
        XCTAssertTrue(view.getCurrentRenderMode() === secondMode)
        XCTAssertTrue(secondMode.program != nil)
    }

    func testResetAllViewportConvertsFiniteDimensions() {
        let view = IRGLView(frame: .zero)

        view.resetAllViewport(w: 320.9, h: 180.2, resetTransform: false)

        XCTAssertEqual(view.viewprotRange, CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    func testResetAllViewportIgnoresInvalidDimensions() {
        let view = IRGLView(frame: .zero)
        view.resetAllViewport(w: 320, h: 180, resetTransform: false)

        view.resetAllViewport(w: .infinity, h: 180, resetTransform: false)

        XCTAssertEqual(view.viewprotRange, CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    func testReloadViewFrameFillsSuperviewWhenAspectIsUnset() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = IRGLView(frame: .zero)
        container.addSubview(view)

        view.aspect = 0
        view.reloadViewFrame()

        XCTAssertEqual(view.frame, container.bounds)
    }

    func testReloadViewFrameLetterboxesWiderContent() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let view = IRGLView(frame: .zero)
        container.addSubview(view)

        view.aspect = 2
        view.reloadViewFrame()

        XCTAssertEqual(view.frame.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(view.frame.origin.y, 40, accuracy: 0.0001)
        XCTAssertEqual(view.frame.width, 320, accuracy: 0.0001)
        XCTAssertEqual(view.frame.height, 160, accuracy: 0.0001)
    }

    func testReloadViewFramePillarboxesTallerContent() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = IRGLView(frame: .zero)
        container.addSubview(view)

        view.aspect = 1
        view.reloadViewFrame()

        XCTAssertEqual(view.frame.origin.x, 70, accuracy: 0.0001)
        XCTAssertEqual(view.frame.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(view.frame.width, 180, accuracy: 0.0001)
        XCTAssertEqual(view.frame.height, 180, accuracy: 0.0001)
    }

    func testReloadViewFrameUsesSuperviewFrameForMatchingAspect() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = IRGLView(frame: .zero)
        container.addSubview(view)

        view.aspect = 320.0 / 180.0
        view.reloadViewFrame()

        XCTAssertEqual(view.frame, container.bounds)
    }

    func testDrawablePixelSizeRejectsInvalidDimensions() {
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: 0, height: 1)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: 1, height: CGFloat.nan)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: CGFloat.infinity, height: 1)))
        XCTAssertNil(IRGLView.drawablePixelSize(from: CGSize(width: CGFloat(Int.max) * 2, height: 1)))
    }

    func testDrawablePixelSizeConvertsFinitePositiveDimensions() {
        let size = IRGLView.drawablePixelSize(from: CGSize(width: 320.9, height: 180.2))

        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 180)
    }

    func testDrawablePixelSizeWrapperMatchesSurfaceOwner() {
        let input = CGSize(width: 320.9, height: 180.2)

        XCTAssertEqual(IRGLView.drawablePixelSize(from: input)?.width,
                       IRGLMetalSurfaceSession.pixelSize(from: input)?.width)
        XCTAssertEqual(IRGLView.drawablePixelSize(from: input)?.height,
                       IRGLMetalSurfaceSession.pixelSize(from: input)?.height)
        XCTAssertNil(
            IRGLMetalSurfaceSession.pixelSize(
                from: CGSize(width: CGFloat.nan, height: 1)
            )
        )
    }

    func testTexUVTextureLayoutRejectsInvalidOrOverflowingInputs() {
        XCTAssertNil(IRGLView.texUVTextureLayout(width: 0, height: 1))
        XCTAssertNil(IRGLView.texUVTextureLayout(width: 1, height: 0))
        XCTAssertNil(IRGLView.texUVTextureLayout(width: Int.max, height: 2))
        XCTAssertNil(IRGLView.texUVTextureLayout(width: Int.max / 8, height: 9))
    }

    func testTexUVTextureLayoutCalculatesRGFloatRows() {
        let layout = IRGLView.texUVTextureLayout(width: 3, height: 2)

        XCTAssertEqual(layout?.bytesPerRow, 24)
        XCTAssertEqual(layout?.totalByteCount, 48)
    }

    func testTexUVTextureLayoutWrapperMatchesRenderStateOwner() {
        let wrapper = IRGLView.texUVTextureLayout(width: 3, height: 2)
        let owner = IRGLViewRenderState.texUVTextureLayout(
            width: 3,
            height: 2
        )

        XCTAssertEqual(wrapper?.bytesPerRow, owner?.bytesPerRow)
        XCTAssertEqual(wrapper?.totalByteCount, owner?.totalByteCount)
        XCTAssertNil(
            IRGLViewRenderState.texUVTextureLayout(
                width: Int.max,
                height: 2
            )
        )
    }

    func testTranslationVectorRejectsInvalidScopeValues() {
        XCTAssertEqual(
            IRGLFrameSubmissionSession.translationVector(for: nil),
            SIMD2<Float>(repeating: 0)
        )
        XCTAssertEqual(
            IRGLFrameSubmissionSession.translationVector(
                for: IRGLScope2D(
                    scaleX: 1,
                    scaleY: 1,
                    offsetX: 0,
                    offsetY: 0,
                    panDegree: 0,
                    w: 0,
                    h: 100
                )
            ),
            SIMD2<Float>(repeating: 0)
        )
        XCTAssertEqual(
            IRGLFrameSubmissionSession.translationVector(
                for: IRGLScope2D(
                    scaleX: .nan,
                    scaleY: 1,
                    offsetX: 0,
                    offsetY: 0,
                    panDegree: 0,
                    w: 100,
                    h: 100
                )
            ),
            SIMD2<Float>(repeating: 0)
        )
        XCTAssertEqual(
            IRGLFrameSubmissionSession.translationVector(
                for: IRGLScope2D(
                    scaleX: 1,
                    scaleY: 1,
                    offsetX: .infinity,
                    offsetY: 0,
                    panDegree: 0,
                    w: 100,
                    h: 100
                )
            ),
            SIMD2<Float>(repeating: 0)
        )
    }

    func testTranslationVectorCalculatesOverflowingAxesFromOffsets() {
        let scope = IRGLScope2D(scaleX: 2, scaleY: 1.5, offsetX: 25, offsetY: 10, panDegree: 0, w: 200, h: 100)
        let vector = IRGLFrameSubmissionSession.translationVector(
            for: scope
        )

        XCTAssertEqual(vector.x, -0.5, accuracy: 0.0001)
        XCTAssertEqual(vector.y, 0.2, accuracy: 0.0001)
    }

    func testTranslationVectorZerosAxesThatFitInsideViewport() {
        let scope = IRGLScope2D(scaleX: 0.75, scaleY: 1.25, offsetX: 80, offsetY: 20, panDegree: 0, w: 200, h: 100)
        let vector = IRGLFrameSubmissionSession.translationVector(
            for: scope
        )

        XCTAssertEqual(vector.x, 0, accuracy: 0.0001)
        XCTAssertEqual(vector.y, -0.25, accuracy: 0.0001)

        let fittedScope = IRGLScope2D(scaleX: 0.75, scaleY: 0.5, offsetX: 80, offsetY: 20, panDegree: 0, w: 200, h: 100)
        XCTAssertEqual(
            IRGLFrameSubmissionSession.translationVector(
                for: fittedScope
            ),
            SIMD2<Float>(repeating: 0)
        )
    }

    func testFittedImageTransformCalculatesAspectFitScaleAndCentering() throws {
        let transform = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFit)
        )

        XCTAssertEqual(transform.scaleX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.25, accuracy: 0.0001)
        XCTAssertEqual(transform.translationX, 0, accuracy: 0.0001)
        XCTAssertEqual(transform.translationY, 25, accuracy: 0.0001)
    }

    func testFittedImageTransformWrapperMatchesFrameOwner() throws {
        let imageExtent = CGRect(x: 10, y: 5, width: 400, height: 200)
        let targetRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let wrapper = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: imageExtent,
                                          targetRect: targetRect,
                                          contentMode: .scaleAspectFit)
        )
        let owner = try XCTUnwrap(
            IRGLFrameSubmissionSession.fittedImageTransform(
                imageExtent: imageExtent,
                targetRect: targetRect,
                contentMode: .scaleAspectFit
            )
        )

        XCTAssertEqual(wrapper.scaleX, owner.scaleX, accuracy: 0.0001)
        XCTAssertEqual(wrapper.scaleY, owner.scaleY, accuracy: 0.0001)
        XCTAssertEqual(
            wrapper.translationX,
            owner.translationX,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            wrapper.translationY,
            owner.translationY,
            accuracy: 0.0001
        )
    }

    func testFittedImageTransformCalculatesAspectFillScaleAndCentering() throws {
        let transform = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFill)
        )

        XCTAssertEqual(transform.scaleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.translationX, -50, accuracy: 0.0001)
        XCTAssertEqual(transform.translationY, 0, accuracy: 0.0001)
    }

    func testFittedImageTransformCalculatesScaleToFillIndependentAxes() throws {
        let transform = try XCTUnwrap(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 80),
                                          contentMode: .scaleToFill)
        )

        XCTAssertEqual(transform.scaleX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(transform.scaleY, 0.4, accuracy: 0.0001)
        XCTAssertEqual(transform.translationX, 0, accuracy: 0.0001)
        XCTAssertEqual(transform.translationY, 0, accuracy: 0.0001)
    }

    func testFittedImageTransformRejectsInvalidGeometry() {
        XCTAssertNil(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 0, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                          contentMode: .scaleAspectFit)
        )
        XCTAssertNil(
            IRGLView.fittedImageTransform(imageExtent: CGRect(x: 0, y: 0, width: 400, height: 200),
                                          targetRect: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 100),
                                          contentMode: .scaleAspectFit)
        )
    }

    private func makePixelBuffer(width: Int,
                                 height: Int,
                                 format: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XCTSkip("CVPixelBuffer unavailable: \(status)")
        }
        return pixelBuffer
    }

    private func makeRGBFrame(width: Int = 2, height: Int = 2) -> IRVideoFrameRGB {
        let bytesPerRow = width * 4
        let frame = IRVideoFrameRGB(linesize: UInt(bytesPerRow),
                                    rgb: Data(repeating: 0xff, count: bytesPerRow * height))
        frame.width = width
        frame.height = height
        return frame
    }

    private func makeFisheyeParameter() -> IRFisheyeParameter {
        IRFisheyeParameter(width: 2,
                           height: 2,
                           up: false,
                           rx: 1,
                           ry: 1,
                           cx: 1,
                           cy: 1,
                           latmax: 90)
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

private final class ViewFlatMultiRenderMode: IRGLRenderModeMulti4P {
    override var programFactory: IRGLProgram2DFactory {
        ViewFlatMultiProgramFactory()
    }
}

private final class ViewFlatMultiProgramFactory: IRGLProgram2DFactory {
    override func createIRGLProgram(pixelFormat: IRPixelFormat,
                                    viewportRange: CGRect,
                                    parameter: IRMediaParameter?) -> IRGLProgram2D? {
        let programs = (0..<4).map { _ in
            IRGLProgram2D(pixelFormat: pixelFormat,
                          viewportRange: viewportRange,
                          parameter: parameter)
        }
        return IRGLProgramMulti4P(programs: programs, viewprotRange: viewportRange)
    }
}

private final class ViewRecordingTransformController: IRGLTransformController {
    private let scope: IRGLScope2D
    private(set) var degreeScrolls: [(x: Float, y: Float)] = []
    private(set) var linearScrolls: [(dx: Float, dy: Float)] = []
    private(set) var updates: [(fx: Float, fy: Float, sx: Float, sy: Float)] = []

    init(scope: IRGLScope2D = IRGLScope2D()) {
        self.scope = scope
        super.init()
    }

    override func getScope() -> IRGLScope2D {
        scope
    }

    override func scroll(degreeX: Float, degreeY: Float) {
        degreeScrolls.append((degreeX, degreeY))
    }

    override func scroll(dx: Float, dy: Float) {
        linearScrolls.append((dx, dy))
    }

    override func update(fx: Float, fy: Float, sx: Float, sy: Float) {
        updates.append((fx, fy, sx, sy))
    }
}

private final class ViewRenderRecorder: IRGLRenderInternal {
    private(set) var renderCallCount = 0
    private(set) var renderMultiCallCount = 0
    private(set) var renderClearCallCount = 0
    private(set) var renderFish2PanoCallCount = 0
    private(set) var renderDistortionCallCount = 0
    private(set) var renderFisheyeCallCount = 0
    private(set) var renderFisheyeMultiCallCount = 0
    private(set) var lastFish2PanoTextureCount = 0
    private(set) var lastFish2PanoOutputSize = CGSize.zero
    private(set) var lastMVPCount = 0
    private(set) var lastViewportCount = 0
    private(set) var lastFrame: IRFFVideoFrame?

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        renderCallCount += 1
        lastFrame = frame
        return true
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        renderMultiCallCount += 1
        lastFrame = frame
        lastViewportCount = viewports.count
        return true
    }

    func renderClear(to drawable: CAMetalDrawable) {
        renderClearCallCount += 1
    }

    func renderFish2Pano(frame: IRFFVideoFrame,
                         params: IRMetalRenderer.Fish2PanoParams,
                         texUVTextures: [MTLTexture],
                         to drawable: CAMetalDrawable,
                         drawableSize: CGSize,
                         viewport: CGRect,
                         contentMode: IRGLRenderContentMode,
                         outputSize: CGSize,
                         zoomScale: Float,
                         translation: SIMD2<Float>) -> Bool {
        renderFish2PanoCallCount += 1
        lastFrame = frame
        lastFish2PanoTextureCount = texUVTextures.count
        lastFish2PanoOutputSize = outputSize
        return true
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        renderDistortionCallCount += 1
        lastFrame = frame
        return true
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        renderFisheyeCallCount += 1
        lastFrame = frame
        lastViewportCount = 1
        return true
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        renderFisheyeMultiCallCount += 1
        lastFrame = frame
        lastMVPCount = mvpList.count
        lastViewportCount = viewports.count
        return true
    }
}
