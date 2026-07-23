//
//  IRGLView.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/8.
//

import UIKit
import AVFoundation
import Metal
import QuartzCore
import CoreImage
import simd

enum IRDisplayRendererType: UInt {
    case empty
    case AVPlayerLayer
    case AVPlayerPixelBufferVR
    case FFmpegPixelBuffer
    case FFmpegPixelBufferVR
}

protocol IRGLViewHost: AnyObject {
    var viewGravityMode: IRGravityMode { get }
}


public class IRGLView: UIView, IRFFDecoderVideoOutput {

    weak var abstractPlayer: (any IRGLViewHost)?
    private var metalLayer: CAMetalLayer? {
        // layerClass is overridden to always return CAMetalLayer.self, so the layer
        // pointer is stable after init. Reading it from any thread is safe; we no
        // longer call syncOnMain here to avoid lock inversion with queue.sync callers.
        layer as? CAMetalLayer
    }
    private var avPlayerLayer: AVPlayerLayer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var ciContext: CIContext?
    private var metalRenderer: IRMetalRenderer?
    private let renderState = IRGLViewRenderState()
    private let renderCoordinator = IRGLViewRenderCoordinator()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var backingWidth: Int = 0
    private var backingHeight: Int = 0
    private var currentImage: CIImage?
    private var currentFrame: IRFFVideoFrame?
    private let queue: DispatchQueue = DispatchQueue(label: "render.queue")
    var irPixelFormat: IRPixelFormat = .YUV_IRPixelFormat {
        didSet {
            initGL(with: irPixelFormat)
        }
    }
    var lastFrameWidth: Int = 0
    var lastFrameHeight: Int = 0
    var willDoSnapshot = false
    var mode: IRGLRenderMode?
    var modes: [IRGLRenderMode] = []
    var viewprotRange: CGRect = .zero
    var aspect: CGFloat = 0.0 {
        didSet {
            guard oldValue != aspect else { return }
            reloadViewFrame()
        }
    }
    var rendererType: IRDisplayRendererType = .empty {
        didSet {
            guard oldValue != rendererType else { return }
            reloadView()
        }
    }
//    weak var avplayer: IRAVPlayer?
    private var renderContentMode: IRGLRenderContentMode = .scaleAspectFit

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initDefaultValue()
        irPixelFormat = .YUV_IRPixelFormat
        initGL(with: irPixelFormat)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        initDefaultValue()
        irPixelFormat = .YUV_IRPixelFormat
        initGL(with: irPixelFormat)
    }

    init(frame: CGRect, player: any IRGLViewHost) {
        self.abstractPlayer = player
        super.init(frame: frame)
        initDefaultValue()
        irPixelFormat = .YUV_IRPixelFormat
        initGL(with: irPixelFormat)
    }

    func initDefaultValue() {
        modes = []
    }

    static public override var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    private func syncOnMain<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }

        return DispatchQueue.main.sync(execute: block)
    }

    func initGL(with pixelFormat: IRPixelFormat) {
        CATransaction.flush()
        // Capture main-thread state before entering queue.sync to avoid lock inversion:
        // queue.sync would block the render queue, and any syncOnMain call from inside
        // it would deadlock if main is simultaneously waiting on queue.sync elsewhere
        // (e.g. layoutSubviews → updateViewPort → queue.sync).
        let (viewBounds, screenScale) = syncOnMain { (bounds, UIScreen.main.scale) }
        guard let metalLayer = self.metalLayer else { return }

        queue.sync {
            reset()
            metalLayer.contentsScale = screenScale
            metalLayer.isOpaque = true
            if device == nil {
                device = MTLCreateSystemDefaultDevice()
            }
            metalLayer.device = device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = false
            commandQueue = device?.makeCommandQueue()
            if let device = device {
                ciContext = CIContext(mtlDevice: device)
                if metalRenderer == nil {
                    metalRenderer = IRMetalRenderer(device: device)
                }
            }
            if ciContext == nil {
                return
            }
            updateDrawableSize(scale: 1.0, metalLayer: metalLayer, viewBounds: viewBounds, screenScale: screenScale)
        }

        viewprotRange = CGRect(x: 0, y: 0, width: backingWidth, height: backingHeight)
        setupModes()
    }

    func close() {
        setAVPlayer(nil)
        queue.sync {
            reset()
        }
    }

    func reset() {
        currentImage = nil
        currentFrame = nil
        metalRenderer = nil
        renderState.reset()
        commandQueue = nil
        ciContext = nil
        device = nil
    }

    deinit {
        reset()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutAVPlayerLayer()
        updateViewPort(1.0)
    }

    func updateViewPort(_ viewportScale: Float) {
        CATransaction.flush()
        guard let metalLayer = self.metalLayer else { return }
        let (viewBounds, screenScale) = syncOnMain { (bounds, UIScreen.main.scale) }
        queue.sync {
            updateDrawableSize(scale: CGFloat(viewportScale), metalLayer: metalLayer, viewBounds: viewBounds, screenScale: screenScale)
        }

        resetAllViewport(w: Float(backingWidth), h: Float(backingHeight), resetTransform: false)
    }

    private func updateDrawableSize(scale: CGFloat, metalLayer: CAMetalLayer, viewBounds: CGRect, screenScale: CGFloat) {
        let effectiveScale = scale * screenScale
        let size = CGSize(width: viewBounds.width * effectiveScale, height: viewBounds.height * effectiveScale)
        guard let pixelSize = Self.drawablePixelSize(from: size) else { return }
        metalLayer.drawableSize = size
        backingWidth = pixelSize.width
        backingHeight = pixelSize.height
    }

    static func drawablePixelSize(from size: CGSize) -> (width: Int, height: Int)? {
        IRGLViewPolicy.drawablePixelSize(from: size)
    }

    public override var contentMode: UIView.ContentMode {
        didSet {
//            changeGLRenderContentMode() // may not need
        }
    }

    func changeGLRenderContentMode() {
        var irGLViewContentMode: IRGLRenderContentMode

        switch abstractPlayer?.viewGravityMode {
        case .resizeAspect:
            irGLViewContentMode = .scaleAspectFit
        case .resizeAspectFill:
            irGLViewContentMode = .scaleAspectFill
        case .resize:
            irGLViewContentMode = .scaleToFill
        default:
            irGLViewContentMode = .scaleAspectFit
        }

        renderContentMode = irGLViewContentMode
        mode?.program?.contentMode = irGLViewContentMode
    }

    func resetAllViewport(w: Float, h: Float, resetTransform: Bool) {
        guard w.isFinite, h.isFinite, w >= 0, h >= 0 else { return }
        let viewportRange = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        guard let viewportSize = IRGLProgram2D.viewportSize(from: viewportRange) else { return }
        viewprotRange = CGRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height)
        mode?.program?.setViewportRange(viewprotRange, resetTransform: resetTransform)
        renderState.resetFisheyeViewport(width: viewportSize.width,
                                         height: viewportSize.height,
                                         resetTransform: resetTransform)
        render(nil)
    }

    func updateScope(byFx fx: Float, fy: Float, dsx: Float, dsy: Float) {
        if let program = mode?.program {
            if let panoProgram = program as? IRGLProgram2DFisheye2Pano,
               let controller = panoProgram.tramsformController {
                let scope = controller.getScope()
                let scaleX = scope.scaleX * dsx
                let scaleY = scope.scaleY * dsy
                let centerX = Float(scope.w) / 2.0
                let centerY = Float(scope.h) / 2.0
                controller.update(fx: centerX, fy: centerY, sx: scaleX, sy: scaleY)
            } else {
                program.didPinchByfx(fx, fy: fy, dsx: dsx, dsy: dsy)
            }
        } else {
            renderState.updateFallbackFisheye(fx: fx, fy: fy, sx: dsx, sy: dsy)
        }
        render(nil)
    }

    func scroll(byDx dx: Float, dy: Float) {
        if let program = mode?.program {
            program.didPanBydx(dx, dy: dy)
            if let panoProgram = program as? IRGLProgram2DFisheye2Pano,
               let params = panoProgram.metalFish2PanoParams,
               let controller = panoProgram.tramsformController {
                let scope = controller.getScope()
                if scope.w > 0, scope.scaleX != 0, params.outputWidth > 0 {
                    let widthScale = Float(params.outputWidth) / Float(scope.w)
                    params.offsetX -= (dx / scope.scaleX * widthScale)
                    let outputWidth = Float(params.outputWidth)
                    while params.offsetX > outputWidth || params.offsetX < -outputWidth {
                        if params.offsetX > outputWidth {
                            params.offsetX -= outputWidth
                        } else if params.offsetX < -outputWidth {
                            params.offsetX += outputWidth
                        }
                    }
                }
            }
        } else {
            renderState.scrollFallbackFisheye(dx: dx, dy: dy)
        }
        render(nil)
    }

    func scroll(byDegreeX degreeX: Float, degreeY: Float) {
        if let program = mode?.program {
            program.didPanByDegreeX(degreeX, degreeY: degreeY)
        } else {
            renderState.scrollFallbackFisheye(degreeX: degreeX, degreeY: degreeY)
        }
        render(nil)
    }

    func render(_ frame: IRFFVideoFrame?) {
        queue.sync {
            if let frame = frame {
                self.lastFrameWidth = Int(frame.width)
                self.lastFrameHeight = Int(frame.height)
                self.currentFrame = frame
                self.currentImage = nil
            }

            self.renderCurrentContent()
        }
    }

    private func renderCurrentContent() {
        guard let metalLayer = metalLayer else { return }
        let result = renderCoordinator.render(
            context: IRGLViewRenderCoordinator.Context(
                metalLayer: metalLayer,
                currentFrame: currentFrame,
                currentImage: currentImage,
                mode: mode,
                fallbackRenderer: metalRenderer,
                renderContentMode: renderContentMode,
                device: device,
                commandQueue: commandQueue,
                ciContext: ciContext,
                colorSpace: colorSpace,
                renderState: renderState,
                makeImage: { [weak self] frame in
                    self?.makeImage(from: frame)
                },
                fitImage: { [weak self] image, rect in
                    self?.fitImage(image, in: rect) ?? image
                }
            )
        )
        currentImage = result.currentImage
        if result.didCompleteRender {
            saveSnapShot()
        }
    }

    private func fitImage(_ image: CIImage, in rect: CGRect) -> CIImage {
        let extent = image.extent
        guard let transform = Self.fittedImageTransform(imageExtent: extent,
                                                        targetRect: rect,
                                                        contentMode: renderContentMode) else {
            return image
        }

        return image
            .transformed(by: CGAffineTransform(scaleX: transform.scaleX, y: transform.scaleY))
            .transformed(by: CGAffineTransform(translationX: transform.translationX, y: transform.translationY))
    }

    struct FittedImageTransform: Equatable {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let translationX: CGFloat
        let translationY: CGFloat
    }

    private static func translationVector(for program: IRGLProgram2D?) -> SIMD2<Float> {
        IRGLViewPolicy.translationVector(for: program?.tramsformController?.getScope())
    }

    static func fittedImageTransform(imageExtent: CGRect,
                                     targetRect: CGRect,
                                     contentMode: IRGLRenderContentMode) -> FittedImageTransform? {
        IRGLViewPolicy.fittedImageTransform(imageExtent: imageExtent,
                                            targetRect: targetRect,
                                            contentMode: contentMode)
    }

    private func clearImage() -> CIImage {
        let size = metalLayer?.drawableSize ?? syncOnMain { bounds.size }
        let rect = CGRect(origin: .zero, size: size)
        return CIImage(color: .black).cropped(to: rect)
    }

    private func makeImage(from frame: IRFFVideoFrame) -> CIImage? {
        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            return CIImage(cvPixelBuffer: cvFrame.pixelBuffer)
        }

        if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            guard let image = yuvFrame.image() else { return nil }
            return CIImage(image: image)
        }

        if let rgbFrame = frame as? IRVideoFrameRGB {
            guard let image = rgbFrame.asImage() else { return nil }
            return CIImage(image: image)
        }

        return nil
    }

    func setRenderModes(_ modes: [IRGLRenderMode]) {
        self.modes = modes
        initGL(with: irPixelFormat)
    }

    func initModes() {
        if modes.isEmpty {
            modes = IRGLRenderModeFactory.createNormalModes(with: nil)
        }

        self.mode = modes.first
    }

    func setupModes() {
        initModes()
        contentMode = .scaleAspectFit
        _ = choose(renderMode: modes.first, withImmediatelyRenderOnce: false)
    }

    func getRenderModes() -> [IRGLRenderMode] {
        return modes
    }

    func getCurrentRenderMode() -> IRGLRenderMode? {
        return mode
    }

    func choose(renderMode: IRGLRenderMode?, withImmediatelyRenderOnce immediatelyRenderOnce: Bool) -> Bool {
        guard let renderMode = renderMode, modes.contains(renderMode) else { return false }

        queue.sync {
            self.mode = renderMode
            self.aspect = CGFloat(self.mode?.aspect ?? 0.0)
            if renderMode.program == nil {
                renderMode.buildIRGLProgram(pixelFormat: irPixelFormat, viewprotRange: viewprotRange, parameter: renderMode.parameter)
            } else {
                renderMode.program?.setViewportRange(viewprotRange, resetTransform: false)
            }
            if renderMode.renderer == nil, let metalRenderer = metalRenderer {
                renderMode.renderer = IRGLRenderStrategyFactory.make(for: renderMode, renderer: metalRenderer)
            }
            setupMetalFisheyeIfNeeded(renderMode: renderMode)
            setupMetalFish2PanoIfNeeded(renderMode: renderMode)

            if immediatelyRenderOnce {
                DispatchQueue.main.async {
                    self.render(nil)
                }
            }
        }

        return true
    }

    func runSyncInQueue(_ block: @escaping () -> Void) {
        queue.sync {
            block()
        }
    }

    func clearCanvas() {
        queue.sync {
            self.currentImage = self.clearImage()
            self.currentFrame = nil
            self.renderCurrentContent()
        }
    }

    func doSnapShot() {
        willDoSnapshot = true
    }

    func saveSnapShot() {
        DispatchQueue.main.async {
            if self.willDoSnapshot {
                self.saveSnapshotAlbum(self.createImageFromFramebuffer())
                self.willDoSnapshot = false
            }
        }
    }

    func saveSnapshotAlbum(_ snapshot: UIImage) {
        IRPhotoSaver.save(snapshot, toAlbum: "Snapshots")
    }

    func createImageFromFramebuffer() -> UIImage {
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else {
            return UIImage()
        }
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer {
            UIGraphicsEndImageContext()
        }
        let containerRect = layer.bounds
        drawHierarchy(in: containerRect, afterScreenUpdates: false)
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    func cleanEmptyBuffer() {
        // Implementation for clean empty buffer
    }

    var attachedAVPlayer: AVPlayer? {
        syncOnMain { avPlayerLayer?.player }
    }

    func setAVPlayer(_ player: AVPlayer?) {
        syncOnMain {
            guard let player else {
                avPlayerLayer?.player = nil
                avPlayerLayer?.removeFromSuperlayer()
                avPlayerLayer = nil
                return
            }

            let playerLayer: AVPlayerLayer
            if let avPlayerLayer {
                playerLayer = avPlayerLayer
            } else {
                playerLayer = AVPlayerLayer()
                avPlayerLayer = playerLayer
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.player = player
            playerLayer.frame = bounds
            playerLayer.videoGravity = avPlayerLayerGravity
            if playerLayer.superlayer !== layer {
                playerLayer.removeFromSuperlayer()
                layer.addSublayer(playerLayer)
            }
            CATransaction.commit()
        }
    }

    private func layoutAVPlayerLayer() {
        guard let avPlayerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        avPlayerLayer.frame = bounds
        CATransaction.commit()
    }

    private func updateAVPlayerLayerGravity() {
        guard let avPlayerLayer else { return }
        avPlayerLayer.videoGravity = avPlayerLayerGravity
    }

    private var avPlayerLayerGravity: AVLayerVideoGravity {
        switch abstractPlayer?.viewGravityMode {
        case .resize:
            return .resize
        case .resizeAspectFill:
            return .resizeAspectFill
        case .resizeAspect, nil:
            return .resizeAspect
        }
    }

    private func setupMetalFish2PanoIfNeeded(renderMode: IRGLRenderMode) {
        renderState.configureFish2Pano(renderMode: renderMode)
    }

    private func setupMetalFisheyeIfNeeded(renderMode: IRGLRenderMode) {
        renderState.configureFisheye(renderMode: renderMode,
                                     viewportSize: CGSize(width: backingWidth, height: backingHeight))
    }

    private func applyFisheyeScopeAndScale(controller: IRGLTransformController3DFisheye,
                                           parameter: IRFisheyeParameter,
                                           renderMode: IRGLRenderMode) {
        if let scaleRange = renderMode.scaleRange {
            controller.scaleRange = scaleRange
        } else if renderMode.defaultScale != 1.0 {
            let old = controller.scaleRange ?? IRGLScaleRange(minScaleX: 1.0, minScaleY: 1.0, maxScaleX: 4.0, maxScaleY: 4.0, defaultScaleX: 1.0, defaultScaleY: 1.0)
            let newScaleRange = IRGLScaleRange(minScaleX: old.minScaleX, minScaleY: old.minScaleY, maxScaleX: old.maxScaleX, maxScaleY: old.maxScaleY, defaultScaleX: renderMode.defaultScale, defaultScaleY: renderMode.defaultScale)
            controller.scaleRange = newScaleRange
        }

        let oldScopeRange = controller.scopeRange ?? IRGLScopeRange(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0, defaultLat: 0, defaultLng: 0)
        let fisheyeScopeRange = IRGLProgramFactoryPolicy.fisheyeScopeRange(from: oldScopeRange, latmax: parameter.latmax)
        controller.scopeRange = IRGLProgramFactoryPolicy.defaultFisheyeScope(from: fisheyeScopeRange, panelIndex: nil)
    }

    static func texUVTextureLayout(width: Int, height: Int) -> (bytesPerRow: Int, totalByteCount: Int)? {
        IRGLViewPolicy.texUVTextureLayout(width: width, height: height)
    }

    public func send(videoFrame: IRFFVideoFrame) {
        render(videoFrame)
    }

    func reloadView() {
        cleanViewIgnore()
        switch rendererType {
        case .empty:
            break
        case .AVPlayerLayer:
            layoutAVPlayerLayer()
        case .AVPlayerPixelBufferVR:
            break
        case .FFmpegPixelBuffer, .FFmpegPixelBufferVR:
            break
        }
        updateDisplayViewLayout(bounds)
    }

    func reloadGravityMode() {
        changeGLRenderContentMode()
        updateAVPlayerLayerGravity()
    }

    func updateDisplayViewLayout(_ frame: CGRect) {
        reloadViewFrame()
        updateViewPort(1.0)
    }

    func reloadViewFrame() {
        guard let superviewFrame = superview?.bounds else { return }
        let superviewAspect = superviewFrame.width / superviewFrame.height

        if aspect <= 0 {
            frame = superviewFrame
            return
        }

        if superviewAspect < aspect {
            let height = superviewFrame.width / aspect
            frame = CGRect(x: 0, y: (superviewFrame.height - height) / 2, width: superviewFrame.width, height: height)
        } else if superviewAspect > aspect {
            let width = superviewFrame.height * aspect
            frame = CGRect(x: (superviewFrame.width - width) / 2, y: 0, width: width, height: superviewFrame.height)
        } else {
            frame = superviewFrame
        }
    }

    func update(frame: CGRect) {
        self.frame = frame
        reloadView()
    }

    func cleanView() {
        cleanViewCleanAVPlayerLayer(true, cleanAVPlayerView: true, cleanFFPlayerView: true)
    }

    func cleanViewIgnore() {
        switch rendererType {
        case .empty:
            cleanView()
        case .AVPlayerLayer:
            cleanViewCleanAVPlayerLayer(false, cleanAVPlayerView: true, cleanFFPlayerView: true)
        case .AVPlayerPixelBufferVR:
            cleanViewCleanAVPlayerLayer(true, cleanAVPlayerView: false, cleanFFPlayerView: true)
        case .FFmpegPixelBuffer, .FFmpegPixelBufferVR:
            cleanViewCleanAVPlayerLayer(true, cleanAVPlayerView: true, cleanFFPlayerView: false)
        }
    }

    func cleanViewCleanAVPlayerLayer(_ cleanAVPlayerLayer: Bool, cleanAVPlayerView: Bool, cleanFFPlayerView: Bool) {
        if cleanAVPlayerLayer {
            setAVPlayer(nil)
        }
        cleanEmptyBuffer()
    }
}

private class IRGLRenderStrategyBase: IRGLRenderInternal {
    private let renderer: IRMetalRenderer

    init(renderer: IRMetalRenderer) {
        self.renderer = renderer
    }

    func render(frame: IRFFVideoFrame,
                to drawable: CAMetalDrawable,
                contentMode: IRGLRenderContentMode,
                drawableSize: CGSize,
                zoomScale: Float,
                translation: SIMD2<Float>) -> Bool {
        renderer.render(frame: frame,
                        to: drawable,
                        contentMode: contentMode,
                        drawableSize: drawableSize,
                        zoomScale: zoomScale,
                        translation: translation)
    }

    func renderMulti(frame: IRFFVideoFrame,
                     to drawable: CAMetalDrawable,
                     drawableSize: CGSize,
                     viewports: [CGRect],
                     contentModes: [IRGLRenderContentMode],
                     zoomScales: [Float],
                     translations: [SIMD2<Float>]) -> Bool {
        renderer.renderMulti(frame: frame,
                             to: drawable,
                             drawableSize: drawableSize,
                             viewports: viewports,
                             contentModes: contentModes,
                             zoomScales: zoomScales,
                             translations: translations)
    }

    func renderClear(to drawable: CAMetalDrawable) {
        renderer.renderClear(to: drawable)
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
        renderer.renderFish2Pano(frame: frame,
                                 params: params,
                                 texUVTextures: texUVTextures,
                                 to: drawable,
                                 drawableSize: drawableSize,
                                 viewport: viewport,
                                 contentMode: contentMode,
                                 outputSize: outputSize,
                                 zoomScale: zoomScale,
                                 translation: translation)
    }

    func renderDistortion(frame: IRFFVideoFrame,
                          leftMesh: IRMetalDistortionMesh,
                          rightMesh: IRMetalDistortionMesh,
                          to drawable: CAMetalDrawable,
                          drawableSize: CGSize,
                          contentMode: IRGLRenderContentMode) -> Bool {
        renderer.renderDistortion(frame: frame,
                                  leftMesh: leftMesh,
                                  rightMesh: rightMesh,
                                  to: drawable,
                                  drawableSize: drawableSize,
                                  contentMode: contentMode)
    }

    func renderFisheye(frame: IRFFVideoFrame,
                       mesh: IRMetalFisheyeMesh,
                       mvp: simd_float4x4,
                       textureMatrix: simd_float4x4,
                       to drawable: CAMetalDrawable,
                       drawableSize: CGSize,
                       viewport: CGRect) -> Bool {
        renderer.renderFisheye(frame: frame,
                               mesh: mesh,
                               mvp: mvp,
                               textureMatrix: textureMatrix,
                               to: drawable,
                               drawableSize: drawableSize,
                               viewport: viewport)
    }

    func renderFisheyeMulti(frame: IRFFVideoFrame,
                            mesh: IRMetalFisheyeMesh,
                            mvpList: [simd_float4x4],
                            textureMatrix: simd_float4x4,
                            to drawable: CAMetalDrawable,
                            drawableSize: CGSize,
                            viewports: [CGRect]) -> Bool {
        renderer.renderFisheyeMulti(frame: frame,
                                    mesh: mesh,
                                    mvpList: mvpList,
                                    textureMatrix: textureMatrix,
                                    to: drawable,
                                    drawableSize: drawableSize,
                                    viewports: viewports)
    }
}

private final class IRGLRenderStrategy2D: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyFish2Pano: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyDistortion: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyFisheye: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyVR: IRGLRenderStrategyBase {}
private final class IRGLRenderStrategyMulti4P: IRGLRenderStrategyBase {}

enum IRGLRenderStrategyKind {
    case twoD
    case fish2Pano
    case distortion
    case fisheye
    case vr
    case multi4P
}

final class IRGLRenderStrategyFactory {
    static func strategyKind(for renderMode: IRGLRenderMode) -> IRGLRenderStrategyKind {
        IRGLRenderStrategyPolicy.strategyKind(for: renderMode)
    }

    static func make(for renderMode: IRGLRenderMode, renderer: IRMetalRenderer) -> IRGLRenderInternal {
        switch strategyKind(for: renderMode) {
        case .distortion:
            return IRGLRenderStrategyDistortion(renderer: renderer)
        case .fish2Pano:
            return IRGLRenderStrategyFish2Pano(renderer: renderer)
        case .vr:
            return IRGLRenderStrategyVR(renderer: renderer)
        case .multi4P:
            return IRGLRenderStrategyMulti4P(renderer: renderer)
        case .fisheye:
            return IRGLRenderStrategyFisheye(renderer: renderer)
        case .twoD:
            return IRGLRenderStrategy2D(renderer: renderer)
        }
    }
}

extension IRGLRenderMode {
    
    func buildIRGLProgram(pixelFormat: IRPixelFormat, viewprotRange: CGRect, parameter: IRMediaParameter?) {
        guard let program = programFactory.createIRGLProgram(pixelFormat: pixelFormat, viewportRange: viewprotRange, parameter: parameter) else {
            self.program = nil
            self.shiftController.program = nil
            return
        }
        self.program = program
        self.shiftController.program = program
//        self.defaultScale = self.defaultScale
//        self.contentMode = self.contentMode
        self.setting()
        self.delegate?.programDidCreate(program)
    }
}
