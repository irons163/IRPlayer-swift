//
//  IRGLProgram2D.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation
import GLKit

protocol IRGLProgramDelegate: AnyObject {
    func didScrollToBounds(_ bounds: IRGLTransformControllerScrollToBounds, withProgram program: IRGLProgram2D)
}

typealias IRGLProgram2DResetScaleBlock = (_ program: IRGLProgram2D) -> Bool

@objcMembers public class IRGLProgram2D: NSObject {

    var program: GLuint = 0
    var vertexShaderString: String?
    var fragmentShaderString: String?
    var pixelFormat: IRPixelFormat
    var shaderParams2D: IRGLShaderParams?
    var renderer: IRGLRender?

    var parameter: IRMediaParameter?
    var transformController: IRGLTransformController?
    var doResetToDefaultScaleBlock: IRGLProgram2DResetScaleBlock?
    public var mapProjection: IRGLProjection?
    weak var delegate: IRGLProgramDelegate?
    var contentMode: IRGLRenderContentMode = .scaleAspectFit {
        didSet {
            if self.contentMode != oldValue {
                updateTextureWidth(UInt(shaderParams2D?.textureWidth ?? 0), height: UInt(shaderParams2D?.textureHeight ?? 0))
            }
        }
    }
    var viewprotRange: CGRect = .zero
    var shouldUpdateToDefaultWhenOutputSizeChanged: Bool = true

    override convenience init() {
        self.init(pixelFormat: .RGB_IRPixelFormat, viewportRange: .zero, parameter: nil)
    }

    public init(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) {
        self.pixelFormat = pixelFormat
        super.init()
        initShaderParams()

        switch pixelFormat {
        case .RGB_IRPixelFormat:
            self.renderer = IRGLRenderRGB()
            print("OK use RGB GL renderer")
        case .YUV_IRPixelFormat:
            self.renderer = IRGLRenderYUV()
            print("OK use YUV GL renderer")
        case .NV12_IRPixelFormat:
            self.renderer = IRGLRenderNV12()
            print("OK use NV12 GL renderer")
        @unknown default:
            break
        }

        setViewportRange(viewportRange)
        self.parameter = parameter
        self.shouldUpdateToDefaultWhenOutputSizeChanged = true
    }

    func initShaderParams() {
        shaderParams2D = IRGLShaderParams()
        shaderParams2D?.delegate = self
    }

    func releaseProgram() {
        if program != 0 {
            glDeleteProgram(program)
            program = 0
        }

        if let renderer = renderer {
            renderer.releaseRender()
            self.renderer = nil
        }
    }

//    func setup(parameter: IRMediaParameter?) {
//        // not implemented yet
//    }

    func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool = true) {
        self.viewprotRange = viewportRange
        transformController?.resetViewport(Int32(viewportRange.width), Int32(viewportRange.height), resetTransform: resetTransform)
    }

    func setDefaultScale(_ scale: Float) {
        if let oldScaleRange = transformController?.scaleRange {
            let newScaleRange = IRGLScaleRange(minScaleX: oldScaleRange.minScaleX, minScaleY: oldScaleRange.minScaleY, maxScaleX: oldScaleRange.maxScaleX, maxScaleY: oldScaleRange.maxScaleY, defaultScaleX: scale, defaultScaleY: scale)
            transformController?.scaleRange = newScaleRange
        }
    }

    func getCurrentScale() -> CGPoint {
        guard let transformController = transformController else { return .zero }
        let defaultScale = transformController.getDefaultTransformScale()
        let scope = transformController.getScope()
        return CGPoint(x: defaultScale.x == 0 ? 0 : CGFloat(scope.scaleX) / defaultScale.x, y: defaultScale.y == 0 ? 0 : CGFloat(scope.scaleY) / defaultScale.y)
    }

    public var tramsformController: IRGLTransformController? {
        get {
            return transformController
        }
        set {
            transformController = newValue
        }
    }

    func touchedInProgram(_ touchedPoint: CGPoint) -> Bool {
        return viewprotRange.contains(touchedPoint)
    }

    func getOutputSize() -> CGSize {
        return CGSize(width: CGFloat(shaderParams2D?.outputWidth ?? 0), height: CGFloat(shaderParams2D?.outputHeight ?? 0))
    }

    func isRendererValid() -> Bool {
        return renderer?.isValid() ?? false
    }

    func loadShaders() -> Bool {
        var result = false
        var vertShader: GLuint = 0
        var fragShader: GLuint = 0

        program = glCreateProgram()

        vertShader = IRGLProgram2D.compileShader(type: GLenum(GL_VERTEX_SHADER), shaderString: vertexShader())
        if vertShader == 0 { return result }

        fragShader = IRGLProgram2D.compileShader(type: GLenum(GL_FRAGMENT_SHADER), shaderString: fragmentShader())
        if fragShader == 0 { return result }

        glAttachShader(program, vertShader)
        glAttachShader(program, fragShader)
        glBindAttribLocation(program, GLuint(ATTRIBUTE_VERTEX), "position")
        glBindAttribLocation(program, GLuint(ATTRIBUTE_TEXCOORD), "texcoord")

        glLinkProgram(program)

        var status: GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &status)
        if status == GL_FALSE {
            print("Failed to link program \(program)")
            return result
        }

        result = IRGLProgram2D.validateProgram(program)

        renderer?.resolveUniforms(program)
        shaderParams2D?.resolveUniforms(program)

        glDeleteShader(vertShader)
        glDeleteShader(fragShader)

        if result {
            print("OK setup GL program")
        } else {
            glDeleteProgram(program)
            program = 0
        }

        return result
    }

    func setRenderFrame(_ frame: IRFFVideoFrame) {
        renderer?.setVideoFrame(frame)
        if frame.width != (shaderParams2D?.textureWidth ?? 0) || frame.height != (shaderParams2D?.textureHeight ?? 0) {
            updateTextureWidth(UInt(frame.width), height: UInt(frame.height))
        }
    }

    func updateTextureWidth(_ width: UInt, height: UInt) {
        shaderParams2D?.updateTextureWidth(width, height: height)
    }

    func setModelviewProj(_ modelviewProj: GLKMatrix4) {
        renderer?.modelviewProj = modelviewProj
    }

    func prepareRender() -> Bool {
        glUseProgram(program)
        shaderParams2D?.prepareRender()
        return renderer?.prepareRender(program) ?? false
    }

    func clearBuffer() {
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }

    func calculateViewport() -> CGRect {
        guard let transformController = transformController else { return .zero }
        let vw = Float(transformController.getScope().w)
        let vh = Float(transformController.getScope().h)

        let w = vw * transformController.getScope().scaleX
        let newX = (-1 * (vw - w)) / 2
        let viewportX = transformController.getScope().scaleX < 1.0 ? newX : 0
        let newY = -1 * (vh - vh * transformController.getScope().scaleY) / 2
        let viewportY = transformController.getScope().scaleY < 1.0 ? newY : 0

        return CGRect(x: viewprotRange.origin.x + CGFloat(viewportX), y: viewprotRange.origin.y + CGFloat(viewportY), width: viewprotRange.width, height: viewprotRange.height)
    }

    func render() {
        let viewport = calculateViewport()
        glViewport(GLint(viewport.origin.x), GLint(viewport.origin.y), GLsizei(viewport.size.width), GLsizei(viewport.size.height))

        if let modelviewProj = transformController?.getModelViewProjectionMatrix() {
            setModelviewProj(modelviewProj)
        }

        if prepareRender() {
            mapProjection?.updateVertex()
            #if DEBUG
            if !IRGLProgram2D.validateProgram(program) {
                print("Failed to validate program")
                return
            }
            #endif
            mapProjection?.draw()
        }
    }

    public func didPanBydx(_ dx: Float, dy: Float) {
        transformController?.scroll(byDx: dx, dy: dy)
    }

    func didPinchByfx(_ fx: Float, fy: Float, sx: Float, sy: Float) {
        guard let scale = transformController?.getScope() else { return }
        transformController?.update(byFx: (Float(scale.w) - (fx * Float(UIScreen.main.scale))), fy: fy * Float(UIScreen.main.scale), sx: sx, sy: sy)
    }

    func didPinchByfx(_ fx: Float, fy: Float, dsx: Float, dsy: Float) {
        guard let scale = transformController?.getScope() else { return }
        let scaleX = scale.scaleX * dsx
        let scaleY = scale.scaleY * dsy

        didPinchByfx(fx, fy: fy, sx: scaleX, sy: scaleY)
    }

    public func didPanByDegreeX(_ degreeX: Float, degreeY: Float) {
        transformController?.scroll(byDegreeX: degreeX, degreey: degreeY)
    }

    func didRotate(_ rotateRadians: Float) {
        transformController?.rotate(rotateRadians * 180 / .pi)
    }

    static func validateProgram(_ prog: GLuint) -> Bool {
        var status: GLint = 0

        glValidateProgram(prog)

        #if DEBUG
        var logLength: GLint = 0
        glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLength)
        if logLength > 0 {
            let log = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
            defer { log.deallocate() }
            glGetProgramInfoLog(prog, logLength, &logLength, log)
            print("Program validate log:\n\(String(cString: log))")
        }
        #endif

        glGetProgramiv(prog, GLenum(GL_VALIDATE_STATUS), &status)
        if status == GL_FALSE {
            print("Failed to validate program \(prog)")
            return false
        }

        return true
    }

    static func compileShader(type: GLenum, shaderString: String) -> GLuint {
        var status: GLint = 0
        let sources = shaderString.cString(using: .utf8)!

        let shader = glCreateShader(type)
        if shader == 0 || shader == GLenum(GL_INVALID_ENUM) {
            print("Failed to create shader \(type)")
            return 0
        }

        sources.withUnsafeBufferPointer { buffer in
            var sourcePtr: UnsafePointer<GLchar>? = buffer.baseAddress
            glShaderSource(shader, 1, &sourcePtr, nil)
        }
        glCompileShader(shader)

        #if DEBUG
        var logLength: GLint = 0
        glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
        if logLength > 0 {
            let log = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
            defer { log.deallocate() }
            glGetShaderInfoLog(shader, logLength, &logLength, log)
            print("Shader compile log:\n\(String(cString: log))")
        }
        #endif

        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        if status == GL_FALSE {
            glDeleteShader(shader)
            print("Failed to compile shader:\n")
            return 0
        }

        return shader
    }

    func didDoubleTap() {
        if let doResetToDefaultScaleBlock = doResetToDefaultScaleBlock, doResetToDefaultScaleBlock(self) {
            return
        }
        transformController?.updateToDefault()
    }

    func vertexShader() -> String {
        vertexShaderString = IRGLVertexShaderGLSL.getShardString()
        return vertexShaderString!
    }

    func fragmentShader() -> String {
        switch pixelFormat {
        case .RGB_IRPixelFormat:
            fragmentShaderString = IRGLFragmentRGBShaderGLSL.getShardString()
        case .YUV_IRPixelFormat:
            fragmentShaderString = IRGLFragmentYUVShaderGLSL.getShardString()
        case .NV12_IRPixelFormat:
            fragmentShaderString = IRGLFragmentNV12ShaderGLSL.getShardString()
        @unknown default:
            break
        }
        return fragmentShaderString!
    }
}

extension IRGLProgram2D: IRGLShaderParamsDelegate {
    
    public func didUpdateOutputWH(_ w: Int32, _ h: Int32) {
        if let transformController = transformController {
            let width = Double(w)
            let height = Double(h)
            let dH = Double(transformController.getScope().h) / height
            let dW = Double(transformController.getScope().w) / width
            var dd: Double

            switch contentMode {
            case .scaleAspectFit:
                dd = min(dH, dW)
            case .scaleAspectFill:
                dd = max(dH, dW)
            case .scaleToFill:
                dd = 0
            @unknown default:
                dd = 0
            }

            if dd > 0 {
                let sy = height * dd / Double(transformController.getScope().h)
                let sx = width * dd / Double(transformController.getScope().w)

                transformController.setupDefaultTransformScaleX(Float(sx), transformScaleY: Float(sy))

                if (dH != 1 || dW != 1) && shouldUpdateToDefaultWhenOutputSizeChanged {
                    transformController.updateToDefault()
                }
            }
        }
    }
}

extension IRGLProgram2D: IRGLTransformControllerDelegate {

    public func willScroll(byDx dx: Float, dy: Float, withTramsformController tramsformController: IRGLTransformController) {
        // No implementation needed
    }

    public func doScrollHorizontal(with status: IRGLTransformControllerScrollStatus, withTramsformController tramsformController: IRGLTransformController) -> Bool {
        return true
    }

    public func doScrollVertical(with status: IRGLTransformControllerScrollStatus, withTramsformController tramsformController: IRGLTransformController) -> Bool {
        return true
    }

    public func didScroll(with status: IRGLTransformControllerScrollStatus, withTramsformController tramsformController: IRGLTransformController) {
        var didScrollToBoundsHorizontal = false
        var didScrollToBoundsVertical = false
        var scrollToBounds: IRGLTransformControllerScrollToBounds = .boundsNone

        if status.contains(.toMaxX) || status.contains(.toMinX) {
            didScrollToBoundsHorizontal = true
            scrollToBounds = .horizontalBounds
        }
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            didScrollToBoundsVertical = true
            scrollToBounds = .verticalBounds
        }

        if didScrollToBoundsHorizontal && didScrollToBoundsVertical {
            scrollToBounds = .horizontalandVerticalBounds
        }

        if let delegate = delegate, scrollToBounds != .boundsNone {
            delegate.didScrollToBounds(scrollToBounds, withProgram: self)
        }
    }
}
