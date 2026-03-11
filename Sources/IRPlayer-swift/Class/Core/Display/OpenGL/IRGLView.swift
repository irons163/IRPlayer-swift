//
//  IRGLView.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/8.
//

import UIKit
import Metal
import QuartzCore
import CoreImage
import GLKit
import simd

enum IRDisplayRendererType: UInt {
    case empty
    case AVPlayerLayer
    case AVPlayerPixelBufferVR
    case FFmpegPixelBuffer
    case FFmpegPixelBufferVR
}

public class IRGLView: UIView, IRFFDecoderVideoOutput {

    var abstractPlayer: IRPlayerImp?
    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var ciContext: CIContext?
    private var metalRenderer: IRMetalRenderer?
    private var metalFisheyeMesh: IRMetalFisheyeMesh?
    private var metalFisheyeController: IRGLTransformController3DFisheye?
    private var metalFisheyeParameter: IRFisheyeParameter?
    private var metalFisheyeLastSize: CGSize = .zero
    private var metalFish2PanoParams: IRGLFish2PanoShaderParams?
    private var metalFish2PanoTexUV: [MTLTexture] = []
    private var metalFish2PanoLastOutputSize: CGSize = .zero
    private var metalFish2PanoLastAntialias: Int = 0
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

    init(frame: CGRect, player: IRPlayerImp) {
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

    func initGL(with pixelFormat: IRPixelFormat) {
        CATransaction.flush()
        queue.sync {
            reset()
            guard let metalLayer = self.layer as? CAMetalLayer else { return }
            metalLayer.contentsScale = UIScreen.main.scale
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
                print("Failed to setup Metal context")
                return
            }
            updateDrawableSize(scale: 1.0)
        }

        viewprotRange = CGRect(x: 0, y: 0, width: backingWidth, height: backingHeight)
        setupModes()
        print("OK setup Metal")
    }

    func close() {
        queue.sync {
            reset()
        }
    }

    func reset() {
        currentImage = nil
        currentFrame = nil
        metalRenderer = nil
        metalFisheyeMesh = nil
        metalFisheyeController = nil
        metalFisheyeParameter = nil
        metalFish2PanoParams = nil
        metalFish2PanoTexUV = []
        metalFish2PanoLastOutputSize = .zero
        metalFish2PanoLastAntialias = 0
        commandQueue = nil
        ciContext = nil
        device = nil
    }

    deinit {
        reset()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateViewPort(1.0)
    }

    func updateViewPort(_ viewportScale: Float) {
        CATransaction.flush()
        queue.sync {
            updateDrawableSize(scale: CGFloat(viewportScale))
        }

        resetAllViewport(w: Float(backingWidth), h: Float(backingHeight), resetTransform: false)
    }

    private func updateDrawableSize(scale: CGFloat) {
        guard let metalLayer = metalLayer else { return }
        let effectiveScale = scale * UIScreen.main.scale
        let size = CGSize(width: bounds.width * effectiveScale, height: bounds.height * effectiveScale)
        guard size.width > 0, size.height > 0 else { return }
        metalLayer.drawableSize = size
        backingWidth = Int(size.width)
        backingHeight = Int(size.height)
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
        viewprotRange = CGRect(x: 0, y: 0, width: Int(w), height: Int(h))
        mode?.program?.setViewportRange(viewprotRange, resetTransform: resetTransform)
        metalFisheyeController?.resetViewport(width: Int(w), height: Int(h), resetTransform: resetTransform)
        render(nil)
    }

    func updateScope(byFx fx: Float, fy: Float, dsx: Float, dsy: Float) {
        metalFisheyeController?.update(fx: fx, fy: fy, sx: dsx, sy: dsy)
        render(nil)
    }

    func scroll(byDx dx: Float, dy: Float) {
        metalFisheyeController?.scroll(dx: dx, dy: dy)
        render(nil)
    }

    func scroll(byDegreeX degreeX: Float, degreeY: Float) {
        metalFisheyeController?.scroll(degreeX: degreeX, degreeY: degreeY)
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
        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        if let frame = currentFrame,
           let renderer = metalRenderer,
           let drawable = metalLayer.nextDrawable() {
            mode?.program?.setRenderFrame(frame)
            if let multiResult = renderMetalMulti4PIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize) {
                if multiResult {
                    saveSnapShot()
                    return
                }
            }
            if let fish2PanoResult = renderMetalFish2PanoIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize) {
                if fish2PanoResult {
                    saveSnapShot()
                    return
                }
            }
            if let fisheyeResult = renderMetalFisheyeIfNeeded(frame: frame, renderer: renderer, drawable: drawable, drawableSize: drawableSize) {
                if fisheyeResult {
                    saveSnapShot()
                    return
                }
            }
            if renderer.render(frame: frame, to: drawable, contentMode: renderContentMode, drawableSize: drawableSize) {
                saveSnapShot()
                return
            }
            if frame is IRFFCVYUVVideoFrame || frame is IRFFAVYUVVideoFrame {
                return
            }
        }

        if currentImage == nil, let frame = currentFrame {
            currentImage = makeImage(from: frame)
        }
        guard let currentImage = currentImage else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciContext = ciContext else { return }

        let targetRect = CGRect(origin: .zero, size: metalLayer.drawableSize)
        guard targetRect.width > 0, targetRect.height > 0 else { return }
        let fittedImage = fitImage(currentImage, in: targetRect)

        ciContext.render(
            fittedImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetRect,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
        saveSnapShot()
    }

    private func fitImage(_ image: CIImage, in rect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, rect.width > 0, rect.height > 0 else {
            return image
        }

        var scaleX = rect.width / extent.width
        var scaleY = rect.height / extent.height

        switch renderContentMode {
        case .scaleAspectFit:
            let scale = min(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        case .scaleAspectFill:
            let scale = max(scaleX, scaleY)
            scaleX = scale
            scaleY = scale
        case .scaleToFill:
            break
        @unknown default:
            break
        }

        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let x = (rect.width - scaledImage.extent.width) / 2.0 - scaledImage.extent.origin.x
        let y = (rect.height - scaledImage.extent.height) / 2.0 - scaledImage.extent.origin.y
        return scaledImage.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private func clearImage() -> CIImage {
        let size = metalLayer?.drawableSize ?? bounds.size
        let rect = CGRect(origin: .zero, size: size)
        return CIImage(color: .black).cropped(to: rect)
    }

    private func makeImage(from frame: IRFFVideoFrame) -> CIImage? {
        if let cvFrame = frame as? IRFFCVYUVVideoFrame {
            return CIImage(cvPixelBuffer: cvFrame.pixelBuffer)
        }

        if let yuvFrame = frame as? IRFFAVYUVVideoFrame {
            let image = yuvFrame.image()
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
        choose(renderMode: modes.first, withImmediatelyRenderOnce: false)
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
        var image: UIImage?
        let size = layer.bounds.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let containerRect = layer.bounds
        drawHierarchy(in: containerRect, afterScreenUpdates: false)
        image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }

    func cleanEmptyBuffer() {
        // Implementation for clean empty buffer
    }

    private func setupMetalFish2PanoIfNeeded(renderMode: IRGLRenderMode) {
        guard let program = renderMode.program as? IRGLProgram2DFisheye2Pano else {
            metalFish2PanoParams = nil
            metalFish2PanoTexUV = []
            metalFish2PanoLastOutputSize = .zero
            metalFish2PanoLastAntialias = 0
            return
        }

        metalFish2PanoParams = program.metalFish2PanoParams
    }

    private func setupMetalFisheyeIfNeeded(renderMode: IRGLRenderMode) {
        guard renderMode is IRGLRenderMode3DFisheye else {
            metalFisheyeController = nil
            metalFisheyeMesh = nil
            metalFisheyeParameter = nil
            return
        }

        if let programController = renderMode.program?.tramsformController as? IRGLTransformController3DFisheye {
            metalFisheyeController = programController
        } else if metalFisheyeController == nil {
            let width = max(backingWidth, 1)
            let height = max(backingHeight, 1)
            metalFisheyeController = IRGLTransformController3DFisheye(viewportWidth: width, viewportHeight: height, tileType: .backward)
        }

        if let parameter = renderMode.parameter as? IRFisheyeParameter {
            metalFisheyeParameter = parameter
        } else {
            metalFisheyeParameter = IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 0)
        }

        // Use program's transform controller defaults (including defaultLat/defaultLng)
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
        let newMaxLat = oldScopeRange.maxLat > 0 ? parameter.latmax : parameter.latmax - 90.0
        var newDefaultLat = oldScopeRange.defaultLat
        if newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat {
            newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2
        }
        let newScopeRange = IRGLScopeRange(minLat: oldScopeRange.minLat, maxLat: newMaxLat, minLng: oldScopeRange.minLng, maxLng: oldScopeRange.maxLng, defaultLat: newDefaultLat, defaultLng: oldScopeRange.defaultLng)
        controller.scopeRange = newScopeRange

        let scopeRange = controller.scopeRange ?? newScopeRange
        let adjustedScopeRange = IRGLScopeRange(minLat: scopeRange.minLat, maxLat: scopeRange.maxLat, minLng: scopeRange.minLng, maxLng: scopeRange.maxLng, defaultLat: -40, defaultLng: 90)
        controller.scopeRange = adjustedScopeRange
    }

    private func renderMetalMulti4PIfNeeded(frame: IRFFVideoFrame,
                                            renderer: IRMetalRenderer,
                                            drawable: CAMetalDrawable,
                                            drawableSize: CGSize) -> Bool? {
        guard let program = mode?.program as? IRGLProgramMulti4P else { return nil }
        let viewports = program.programs.map { $0.viewprotRange }
        let contentModes = program.programs.map { $0.contentMode }
        return renderer.renderMulti(frame: frame,
                                    to: drawable,
                                    drawableSize: drawableSize,
                                    viewports: viewports,
                                    contentModes: contentModes)
    }

    private func renderMetalFish2PanoIfNeeded(frame: IRFFVideoFrame,
                                              renderer: IRMetalRenderer,
                                              drawable: CAMetalDrawable,
                                              drawableSize: CGSize) -> Bool? {
        guard mode is IRGLRenderMode2DFisheye2Pano else { return nil }
        guard let params = metalFish2PanoParams else { return false }
        let outputWidth = Int(params.outputWidth)
        let outputHeight = Int(params.outputHeight)
        let antialias = Int(params.antialias)
        guard outputWidth > 0, outputHeight > 0, antialias > 0 else { return false }

        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        if outputSize != metalFish2PanoLastOutputSize || antialias != metalFish2PanoLastAntialias {
            metalFish2PanoTexUV = []
            metalFish2PanoLastOutputSize = outputSize
            metalFish2PanoLastAntialias = antialias
        }

        if let pixUV = params.consumePixUVIfReady() {
            let texCount = min(pixUV.count, antialias * antialias)
            var newTextures: [MTLTexture] = []
            newTextures.reserveCapacity(texCount)
            for i in 0..<texCount {
                guard let texture = makeTexUVTexture(width: outputWidth,
                                                     height: outputHeight,
                                                     data: pixUV[i]) else {
                    continue
                }
                newTextures.append(texture)
            }
            if !newTextures.isEmpty {
                metalFish2PanoTexUV = newTextures
            }
        }

        guard metalFish2PanoTexUV.count == antialias * antialias else {
            renderer.renderClear(to: drawable)
            return true
        }

        let viewportRect = (mode?.program as? IRGLProgram2D)?.calculateViewport() ??
            CGRect(x: 0, y: 0, width: drawableSize.width, height: drawableSize.height)

        let renderParams = IRMetalRenderer.Fish2PanoParams(
            fishwidth: Int32(params.textureWidth),
            fishheight: Int32(params.textureHeight),
            panowidth: Int32(outputWidth),
            panoheight: Int32(outputHeight),
            antialias: Int32(antialias),
            offsetX: params.offsetX
        )

        let effectiveContentMode = (mode?.program as? IRGLProgram2D)?.contentMode ?? renderContentMode
        return renderer.renderFish2Pano(frame: frame,
                                        params: renderParams,
                                        texUVTextures: metalFish2PanoTexUV,
                                        to: drawable,
                                        drawableSize: drawableSize,
                                        viewport: viewportRect,
                                        contentMode: effectiveContentMode,
                                        outputSize: outputSize)
    }

    private func makeTexUVTexture(width: Int, height: Int, data: UnsafeMutablePointer<GLfloat>) -> MTLTexture? {
        guard let device = device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let bytesPerRow = width * MemoryLayout<Float>.size * 2
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        return texture
    }

    private func renderMetalFisheyeIfNeeded(frame: IRFFVideoFrame,
                                            renderer: IRMetalRenderer,
                                            drawable: CAMetalDrawable,
                                            drawableSize: CGSize) -> Bool? {
        guard mode is IRGLRenderMode3DFisheye else { return nil }
        guard let controller = metalFisheyeController else { return false }
        guard let parameter = metalFisheyeParameter else { return false }

        let textureWidth = parameter.width > 0 ? parameter.width : Float(frame.width)
        let textureHeight = parameter.height > 0 ? parameter.height : Float(frame.height)
        let meshSize = CGSize(width: CGFloat(textureWidth), height: CGFloat(textureHeight))
        if metalFisheyeMesh == nil || metalFisheyeLastSize != meshSize {
            let device = self.device ?? MTLCreateSystemDefaultDevice()
            if let device = device {
                if let projection = mode?.program?.mapProjection as? IRGLProjectionEquirectangular,
                   let meshData = projection.exportMesh() {
                    metalFisheyeMesh = IRMetalFisheyeMesh(device: device,
                                                          positions: meshData.positions,
                                                          texcoords: meshData.texcoords,
                                                          indices: meshData.indices)
                } else {
                    metalFisheyeMesh = IRMetalFisheyeMesh(device: device,
                                                          textureWidth: textureWidth,
                                                          textureHeight: textureHeight,
                                                          centerX: parameter.cx,
                                                          centerY: parameter.cy,
                                                          radius: parameter.ry)
                }
                metalFisheyeLastSize = meshSize
            }
        }

        guard let mesh = metalFisheyeMesh else { return false }
        let mvp = controller.getModelViewProjectionMatrix()
        let texMatrix = GLKMatrix4MakeScale(1, -1, 1)

        let viewportRect = (mode?.program as? IRGLProgram2D)?.calculateViewport() ??
            CGRect(x: 0, y: 0, width: drawableSize.width, height: drawableSize.height)

        return renderer.renderFisheye(frame: frame,
                                      mesh: mesh,
                                      mvp: mvp.simd.toMetalClipSpace(),
                                      textureMatrix: texMatrix.simd,
                                      to: drawable,
                                      drawableSize: drawableSize,
                                      viewport: viewportRect)
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
            break
        case .AVPlayerPixelBufferVR:
            break
        case .FFmpegPixelBuffer, .FFmpegPixelBufferVR:
            break
        }
        updateDisplayViewLayout(bounds)
    }

    func reloadGravityMode() {
        changeGLRenderContentMode()
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
        cleanEmptyBuffer()
    }
}

extension IRGLRenderMode {
    
    func buildIRGLProgram(pixelFormat: IRPixelFormat, viewprotRange: CGRect, parameter: IRMediaParameter?) {
        let program = programFactory.createIRGLProgram(pixelFormat: pixelFormat, viewportRange: viewprotRange, parameter: parameter)
        self.program = program
        self.shiftController.program = program
//        self.defaultScale = self.defaultScale
//        self.contentMode = self.contentMode
        self.setting()
        self.delegate?.programDidCreate(program)
    }
}

private extension GLKMatrix4 {
    var simd: simd_float4x4 {
        return simd_float4x4(columns: (
            SIMD4<Float>(m00, m01, m02, m03),
            SIMD4<Float>(m10, m11, m12, m13),
            SIMD4<Float>(m20, m21, m22, m23),
            SIMD4<Float>(m30, m31, m32, m33)
        ))
    }
}
private extension simd_float4x4 {
    func toMetalClipSpace() -> simd_float4x4 {
        let clip = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 0.5, 0),
            SIMD4<Float>(0, 0, 0.5, 1)
        ))
        return clip * self
    }
}
