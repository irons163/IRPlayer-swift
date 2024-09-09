//
//  IRGLProgramDistortion.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/24.
//

import OpenGLES

@objcMembers public class IRGLProgramDistortion: IRGLProgram2D {

    let vertexShaderString2 = """
        attribute vec2 aPosition;
        attribute float aVignette;
        attribute vec2 aRedTextureCoord;
        attribute vec2 aGreenTextureCoord;
        attribute vec2 aBlueTextureCoord;
        varying vec2 vRedTextureCoord;
        varying vec2 vBlueTextureCoord;
        varying vec2 vGreenTextureCoord;
        varying float vVignette;
        uniform float uTextureCoordScale;
        void main() {
            gl_Position = vec4(aPosition, 0.0, 1.0);
            vRedTextureCoord = aRedTextureCoord.xy * uTextureCoordScale;
            vGreenTextureCoord = aGreenTextureCoord.xy * uTextureCoordScale;
            vBlueTextureCoord = aBlueTextureCoord.xy * uTextureCoordScale;
            vVignette = aVignette;
        }
    """

    let fragmentShaderString2 = """
        precision mediump float;
        varying vec2 vRedTextureCoord;
        varying vec2 vBlueTextureCoord;
        varying vec2 vGreenTextureCoord;
        varying float vVignette;
        uniform sampler2D uTextureSampler;
        void main() {
            gl_FragColor = vVignette * vec4(texture2D(uTextureSampler, vRedTextureCoord).r,
                                            texture2D(uTextureSampler, vGreenTextureCoord).g,
                                            texture2D(uTextureSampler, vBlueTextureCoord).b, 1.0);
        }
    """



//    var transformController: IRGLTransformController? {
//        return IRGLTransformControllerDistortion
//    }

    var transformControllerDistortion: IRGLTransformControllerDistortion? {
        return transformController as? IRGLTransformControllerDistortion
    }

    var indexCount: Int = 0
    public var indexBufferID: GLint = 0
    public var vertexBufferID: GLint = 0

    private var previousFrameBufferID: GLint = 0
    private var frameBufferID: GLuint = 0
    private var colorRenderID: GLuint = 0
    private var frameTextureID: GLuint = 0

    private var programID: GLuint = 0
    private var vertexShaderID: GLuint = 0
    private var fragmentShaderID: GLuint = 0

    private var positionShaderLocation: GLint = 0
    private var vignetteShaderLocation: GLint = 0
    private var redTextureCoordShaderLocation: GLint = 0
    private var greenTextureCoordShaderLocation: GLint = 0
    private var blueTextureCoordShaderLocation: GLint = 0
    private var textureCoordScaleShaderLocation: GLint = 0
    private var textureSamplerShaderLocation: GLint = 0

    var viewportSize: CGSize = .zero {
        didSet {
            guard viewportSize != oldValue else { return }
            resetFrameBufferSize()
        }
    }

    private lazy var leftEye: IRGLProjectionDistortion? = IRGLProjectionDistortion(modelType: .left)
    private lazy var rightEye: IRGLProjectionDistortion? = IRGLProjectionDistortion(modelType: .right)

    override func vertexShader() -> String {
        return IRGLVertexShaderGLSL.getShardString()
    }

    override func fragmentShader() -> String {
        switch pixelFormat {
        case .RGB_IRPixelFormat:
            return IRGLFragmentRGBShaderGLSL.getShardString()
        case .YUV_IRPixelFormat:
            return IRGLFragmentYUVShaderGLSL.getShardString()
        case .NV12_IRPixelFormat:
            return IRGLFragmentNV12ShaderGLSL.getShardString()
        @unknown default:
            return ""
        }
    }

    public override init(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) {
        super.init(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
        self.viewportSize = viewportRange.size
        setup()
    }

    override func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool) {
        super.setViewportRange(viewportRange, resetTransform: resetTransform)
        transformControllerDistortion?.resetViewport(width: Int(viewportRange.size.width) / 2, height: Int(viewportRange.size.height), resetTransform: false)
        viewportSize = viewportRange.size
    }

    func drawBox() {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(previousFrameBufferID))

        let viewport = calculateViewport()
        glViewport(GLint(viewport.origin.x), GLint(viewport.origin.y), GLsizei(viewport.size.width), GLsizei(viewport.size.height))

        glDisable(GLenum(GL_CULL_FACE))
        glDisable(GLenum(GL_SCISSOR_TEST))

        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))

        glEnable(GLenum(GL_SCISSOR_TEST))

        glScissor(GLint(viewport.origin.x), GLint(viewport.origin.y), GLsizei(viewport.size.width / 2), GLsizei(viewport.size.height))
        draw(eye: leftEye)
        glScissor(GLint(viewport.origin.x + viewport.size.width / 2), GLint(viewport.origin.y), GLsizei(viewport.size.width / 2), GLsizei(viewport.size.height))
        draw(eye: rightEye)

        glDisable(GLenum(GL_SCISSOR_TEST))
    }

    func draw() {
        if prepareRender() {
            mapProjection?.updateVertex()
        }
    }

    override func render() {
        let viewport = calculateViewport()

        beforeDrawFrame()

        glViewport(GLint(viewport.origin.x), GLint(viewport.origin.y), GLsizei(viewport.size.width / 2), GLsizei(viewport.size.height))
        mapProjection?.updateVertex()
        transformControllerDistortion?.resetViewport(width: Int(viewport.size.width) / 2, height: Int(viewport.size.height), resetTransform: false)
        if let transformController = transformController {
            setModelviewProj(transformController.getModelViewProjectionMatrix())
        }

        if prepareRender() {
            mapProjection?.draw()
        }

        glViewport(GLint(viewport.origin.x + viewport.size.width / 2), GLint(viewport.origin.y), GLsizei(viewport.size.width / 2), GLsizei(viewport.size.height))
        transformControllerDistortion?.resetViewport(width: Int(viewport.size.width) / 2, height: Int(viewport.size.height), resetTransform: false)
        if let transformControllerDistortion = transformControllerDistortion {
            setModelviewProj(transformControllerDistortion.getModelViewProjectionMatrix2())
        }

        if prepareRender() {
            mapProjection?.draw()
        }

        drawBox()
    }

    public override func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            return false
        }
        return true
    }

    private func beforeDrawFrame() {
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &previousFrameBufferID)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBufferID)
    }

    private func draw(eye: IRGLProjectionDistortion?) {
        useProgram()

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), GLuint(eye?.vertex_buffer_id ?? 0))
        glVertexAttribPointer(GLuint(positionShaderLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(9 * MemoryLayout<Float>.size), UnsafeRawPointer(bitPattern: 0))
        glEnableVertexAttribArray(GLuint(positionShaderLocation))
        glVertexAttribPointer(GLuint(vignetteShaderLocation), 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(9 * MemoryLayout<Float>.size), UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.size))
        glEnableVertexAttribArray(GLuint(vignetteShaderLocation))
        glVertexAttribPointer(GLuint(blueTextureCoordShaderLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(9 * MemoryLayout<Float>.size), UnsafeRawPointer(bitPattern: 7 * MemoryLayout<Float>.size))
        glEnableVertexAttribArray(GLuint(blueTextureCoordShaderLocation))

        glVertexAttribPointer(GLuint(redTextureCoordShaderLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(9 * MemoryLayout<Float>.size), UnsafeRawPointer(bitPattern: 3 * MemoryLayout<Float>.size))
        glEnableVertexAttribArray(GLuint(redTextureCoordShaderLocation))
        glVertexAttribPointer(GLuint(greenTextureCoordShaderLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(9 * MemoryLayout<Float>.size), UnsafeRawPointer(bitPattern: 5 * MemoryLayout<Float>.size))
        glEnableVertexAttribArray(GLuint(greenTextureCoordShaderLocation))

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), frameTextureID)

        glUniform1i(textureSamplerShaderLocation, 0)
        let resolutionScale: Float = 1
        glUniform1f(textureCoordScaleShaderLocation, resolutionScale)

        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), GLuint(eye?.index_buffer_id ?? 0))
        glDrawElements(GLenum(GL_TRIANGLE_STRIP), GLsizei(eye?.index_count ?? 0), GLenum(GL_UNSIGNED_SHORT), nil)
    }

    private func setup() {
        setupFrameBuffer()
        setupProgramAndShader()
        resetFrameBufferSize()
    }

    private func useProgram() {
        glUseProgram(programID)
    }

    private func setupFrameBuffer() {
        glGenTextures(1, &frameTextureID)
        glBindTexture(GLenum(GL_TEXTURE_2D), frameTextureID)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)

        checkGLError()

        glGenRenderbuffers(1, &colorRenderID)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderID)

        checkGLError()

        glGenFramebuffers(1, &frameBufferID)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBufferID)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), frameTextureID, 0)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_RENDERBUFFER), colorRenderID)

        checkGLError()
    }

    private func resetFrameBufferSize() {
        glBindTexture(GLenum(GL_TEXTURE_2D), frameTextureID)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB, GLsizei(viewportSize.width), GLsizei(viewportSize.height), 0, GLenum(GL_RGB), GLenum(GL_UNSIGNED_BYTE), nil)

        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderID)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), GLsizei(viewportSize.width), GLsizei(viewportSize.height))
        checkGLError()
    }

    private func setupProgramAndShader() {
        programID = glCreateProgram()

        if !compileShader(&vertexShaderID, type: GLenum(GL_VERTEX_SHADER), string: vertexShaderString2) {
            print("load vertex shader failure")
        }
        if !compileShader(&fragmentShaderID, type: GLenum(GL_FRAGMENT_SHADER), string: fragmentShaderString2) {
            print("load fragment shader failure")
        }
        glAttachShader(programID, vertexShaderID)
        glAttachShader(programID, fragmentShaderID)

        var status: GLint = 0
        glLinkProgram(programID)

        glGetProgramiv(programID, GLenum(GL_LINK_STATUS), &status)

        if status == GL_FALSE {
            print("link program failure")
        }

        clearShader()

        positionShaderLocation = glGetAttribLocation(programID, "aPosition")
        if positionShaderLocation == -1 {
            fatalError("Could not get attrib location for aPosition")
        }

        vignetteShaderLocation = glGetAttribLocation(programID, "aVignette")
        if vignetteShaderLocation == -1 {
            fatalError("Could not get attrib location for aVignette")
        }

        redTextureCoordShaderLocation = glGetAttribLocation(programID, "aRedTextureCoord")
        if redTextureCoordShaderLocation == -1 {
            fatalError("Could not get attrib location for aRedTextureCoord")
        }

        greenTextureCoordShaderLocation = glGetAttribLocation(programID, "aGreenTextureCoord")
        if greenTextureCoordShaderLocation == -1 {
            fatalError("Could not get attrib location for aGreenTextureCoord")
        }

        blueTextureCoordShaderLocation = glGetAttribLocation(programID, "aBlueTextureCoord")
        if blueTextureCoordShaderLocation == -1 {
            fatalError("Could not get attrib location for aBlueTextureCoord")
        }

        textureCoordScaleShaderLocation = glGetUniformLocation(programID, "uTextureCoordScale")
        if textureCoordScaleShaderLocation == -1 {
            fatalError("Could not get attrib location for uTextureCoordScale")
        }

        textureSamplerShaderLocation = glGetUniformLocation(programID, "uTextureSampler")
        if textureSamplerShaderLocation == -1 {
            fatalError("Could not get attrib location for uTextureSampler")
        }

        useProgram()
    }

    private func compileShader(_ shader: inout GLuint, type: GLenum, string: String) -> Bool {
        guard let shaderString = string.cString(using: .utf8) else {
            print("Failed to load shader")
            return false
        }

        var status: GLint = 0

        shader = glCreateShader(type)
        shaderString.withUnsafeBufferPointer { pointer in
            var shaderCStringPointer: UnsafePointer<GLchar>? = pointer.baseAddress
            glShaderSource(shader, 1, &shaderCStringPointer, nil)
        }
//        var shaderStringPointer: UnsafePointer<GLchar>? = shaderString
//        glShaderSource(shader, 1, &shaderStringPointer, nil)
        glCompileShader(shader)
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        if status != GL_TRUE {
            var logLength: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if logLength > 0 {
                let log = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
                glGetShaderInfoLog(shader, logLength, &logLength, log)
                print("Shader compile log:\n\(String(cString: log))")
                log.deallocate()
            }
        }

        return status == GL_TRUE
    }

    private func clearShader() {
        if vertexShaderID != 0 {
            glDeleteShader(vertexShaderID)
        }

        if fragmentShaderID != 0 {
            glDeleteShader(fragmentShaderID)
        }
    }

    private func checkGLError() {
        let err = glGetError()
        if err != GL_NO_ERROR {
            print("glError: \(String(format: "0x%04X", err))")
        }
    }
}
