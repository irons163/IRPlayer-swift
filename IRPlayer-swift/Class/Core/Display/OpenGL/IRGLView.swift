//
//  IRGLView.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/8.
//

import UIKit
import OpenGLES
import QuartzCore
import AssetsLibrary

enum IRDisplayRendererType: UInt {
    case empty
    case AVPlayerLayer
    case AVPlayerPixelBufferVR
    case FFmpegPixelBuffer
    case FFmpegPixelBufferVR
}

public class IRGLView: UIView, IRFFDecoderVideoOutput {

    var abstractPlayer: IRPlayerImp?
    var context: EAGLContext?
    var framebuffer: GLuint = 0
    var renderbuffer: GLuint = 0
    var backingWidth: GLint = 0
    var backingHeight: GLint = 0
    var viewportWidth: GLint = 0
    var viewportHeight: GLint = 0
    private let queue: DispatchQueue = DispatchQueue(label: "render.queue")
    var irPixelFormat: IRPixelFormat = .YUV_IRPixelFormat {
        didSet {
            initGL(with: irPixelFormat)
        }
    }
    var programs: [IRGLProgram2D] = []
    var currentProgram: IRGLProgram2D?
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
        return CAEAGLLayer.self
    }

    func setupContext() -> EAGLContext? {
        var context: EAGLContext? = EAGLContext(api: .openGLES3)
        if context == nil {
            context = EAGLContext(api: .openGLES2)
        }
        return context
    }

    func initGL(with pixelFormat: IRPixelFormat) {
        CATransaction.flush()
        EAGLContext.setCurrent(context)
        guard let eaglLayer = self.layer as? CAEAGLLayer else { return }
        queue.sync {
            reset()
            eaglLayer.contentsScale = UIScreen.main.scale
            eaglLayer.isOpaque = true
            eaglLayer.drawableProperties = [
                kEAGLDrawablePropertyRetainedBacking: false,
                kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
            ]

            context = setupContext()

            guard let context = context, EAGLContext.setCurrent(context) else {
                print("Failed to setup EAGLContext")
                return
            }

            glGenFramebuffers(1, &framebuffer)
            glGenRenderbuffers(1, &renderbuffer)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
            glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
            context.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer)
            glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &backingWidth)
            glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &backingHeight)
            glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), renderbuffer)

            let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
            if status != GL_FRAMEBUFFER_COMPLETE {
                print("Failed to make complete framebuffer object \(status)")
                return
            }

            let glError = glGetError()
            if glError != GL_NO_ERROR {
                print("Failed to setup GL \(glError)")
                return
            }
        }

        viewprotRange = CGRect(x: 0, y: 0, width: Int(backingWidth), height: Int(backingHeight))
        setupModes()
        print("OK setup GL")
    }

    func close() {
        queue.sync {
            EAGLContext.setCurrent(context)
            reset()
        }
    }

    func reset() {
        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }

        if renderbuffer != 0 {
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glDeleteRenderbuffers(1, &renderbuffer)
            renderbuffer = 0
        }

        for program in programs {
            program.release()
        }
        programs = []

        if EAGLContext.current() == context {
            EAGLContext.setCurrent(nil)
        }

        context = nil
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
            let hasLoadShaders = !(self.backingWidth == 0 && self.backingHeight == 0)

            EAGLContext.setCurrent(self.context)
            guard let eaglLayer = self.layer as? CAEAGLLayer else { return }
            eaglLayer.contentsScale = CGFloat(viewportScale) * UIScreen.main.scale
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffer)
            glBindRenderbuffer(GLenum(GL_RENDERBUFFER), self.renderbuffer)
            self.context?.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer)
            glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &self.backingWidth)
            glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &self.backingHeight)
            print("_backingWidth: \(self.backingWidth)")

            if !hasLoadShaders && (self.backingWidth != 0 || self.backingHeight != 0) {
                self.loadShaders()
            }
        }

        resetAllViewport(w: Float(backingWidth), h: Float(backingHeight), resetTransform: true)
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

        for program in programs {
            program.contentMode = irGLViewContentMode
        }
    }

    func resetAllViewport(w: Float, h: Float, resetTransform: Bool) {
        viewprotRange = CGRect(x: 0, y: 0, width: Int(w), height: Int(h))

        for program in programs {
            program.setViewprotRange(CGRect(x: 0, y: 0, width: Int(w), height: Int(h)), resetTransform: false)
        }
        render(nil)
    }

    func updateScope(byFx fx: Float, fy: Float, dsx: Float, dsy: Float) {
        currentProgram?.didPinchByfx(fx, fy: fy, dsx: dsx, dsy: dsy)
        render(nil)
    }

    func scroll(byDx dx: Float, dy: Float) {
        currentProgram?.didPanBydx(dx, dy: dy)
        render(nil)
    }

    func scroll(byDegreeX degreeX: Float, degreeY: Float) {
        currentProgram?.didPan(byDegreeX: degreeX, degreey: degreeY)
        render(nil)
    }

    func render(_ frame: IRFFVideoFrame?) {
        guard let currentProgram = currentProgram else { return }

        queue.sync {
            self.setCurrentContext()
            self.bindCurrentFramebuffer()

            if let frame = frame {
                currentProgram.setRenderFrame(frame)
                self.lastFrameWidth = Int(frame.width)
                self.lastFrameHeight = Int(frame.height)
            }

            currentProgram.clearBuffer()
            currentProgram.render()
            self.bindCurrentRenderBuffer()
            _ = self.presentRenderBuffer()
            self.saveSnapShot()
        }
    }

    func setRenderModes(_ modes: [IRGLRenderMode]) {
        self.modes = modes
        initGL(with: irPixelFormat)
    }

    func initModes() {
        var array: [IRGLProgram2D] = []
        if modes.isEmpty {
            modes = IRGLRenderModeFactory.createNormalModes(with: nil)
        }

        for mode in modes {
            mode.buildIRGLProgram(pixelFormat: irPixelFormat, viewprotRange: viewprotRange, parameter: mode.parameter)
            if let program = mode.program {
                array.append(program)
            }
        }

        programs = array
    }

    func loadShaders() {
        EAGLContext.setCurrent(context)
        for program in programs {
            if !program.loadShaders() {
                return
            }
        }
    }

    func setupModes() {
        initModes()
        DispatchQueue.global().sync {
            self.loadShaders()
        }
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
            self.currentProgram = self.mode?.program
            self.mode?.shiftController.setProgram(self.currentProgram!)
            self.currentProgram?.updateTextureWidth(UInt(lastFrameWidth), height: UInt(lastFrameHeight))
            self.aspect = CGFloat(self.mode?.aspect ?? 0.0)

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

    func setCurrentContext() {
        EAGLContext.setCurrent(context)
    }

    func bindCurrentFramebuffer() {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
    }

    func presentRenderBuffer() -> Bool {
        return context?.presentRenderbuffer(Int(GL_RENDERBUFFER)) ?? false
    }

    func bindCurrentRenderBuffer() {
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
    }

    func clearCurrentBuffer() {
        currentProgram?.clearBuffer()
    }

    func clearCanvas() {
        guard currentProgram != nil else { return }

        queue.sync {
            self.setCurrentContext()
            self.bindCurrentFramebuffer()
            self.clearCurrentBuffer()
            self.bindCurrentRenderBuffer()
            self.presentRenderBuffer()
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
        let library = ALAssetsLibrary()

        library.writeImage(toSavedPhotosAlbum: snapshot.cgImage, orientation: ALAssetOrientation(rawValue: snapshot.imageOrientation.rawValue)!) { (assetURL, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }

            library.asset(for: assetURL!, resultBlock: { (asset) in
                library.enumerateGroups(withTypes: ALAssetsGroupType(ALAssetsGroupAlbum)) { (group, stop) in
                    // Handle group
                } failureBlock: { (error) in
                    print("Error: \(error?.localizedDescription)")
                }
            }, failureBlock: { (error) in
                print("Error loading asset")
            })
        }
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

    public func decoder(_ decoder: IRFFDecoder?, renderVideoFrame videoFrame: IRFFVideoFrame) {
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
        let program = programFactory.createIRGLProgram(with: pixelFormat, withViewprotRange: viewprotRange, with: parameter)
        self.program = program
        self.shiftController.setProgram(program)
//        self.defaultScale = self.defaultScale
//        self.contentMode = self.contentMode
        self.setting()
        self.delegate?.programDidCreate(program)
    }
}
