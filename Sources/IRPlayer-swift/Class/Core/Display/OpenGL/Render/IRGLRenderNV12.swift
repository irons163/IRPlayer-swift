//
//  IRGLRenderNV12.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/18.
//

import Foundation
import OpenGLES
import AVFoundation

enum UniformSampler: Int {
    case y
    case uv
    static let count = 2
}

enum UniformParam: Int {
    case colorConversionMatrix
    case lumaThreshold
    case chromaThreshold
    static let count = 3
}

@objcMembers public class IRGLRenderNV12: IRGLRenderBase {

    private var uniformSamplers = [GLint](repeating: 0, count: UniformSampler.count)
    private var uniformParams = [GLint](repeating: 0, count: UniformParam.count)
    private var textures = [GLuint](repeating: 0, count: 2)

    private var lumaTexture: CVOpenGLESTexture?
    private var chromaTexture: CVOpenGLESTexture?
    private var videoTextureCache: CVOpenGLESTextureCache?
    private var preferredConversion: [GLfloat] = kIRColorConversion709

    var chromaThreshold: GLfloat = 1.0
    var lumaThreshold: GLfloat = 1.0

    public override init() {
        super.init()
        self.preferredConversion = kIRColorConversion709
        self.lumaThreshold = 1.0
        self.chromaThreshold = 1.0
    }

    public override func isValid() -> Bool {
        return lumaTexture != nil
    }

    public override func resolveUniforms(_ program: GLuint) {
        super.resolveUniforms(program)

        uniformSamplers[UniformSampler.y.rawValue] = glGetUniformLocation(program, "SamplerY")
        uniformSamplers[UniformSampler.uv.rawValue] = glGetUniformLocation(program, "SamplerUV")

        uniformParams[UniformParam.colorConversionMatrix.rawValue] = glGetUniformLocation(program, "colorConversionMatrix")
        uniformParams[UniformParam.lumaThreshold.rawValue] = glGetUniformLocation(program, "lumaThreshold")
        uniformParams[UniformParam.chromaThreshold.rawValue] = glGetUniformLocation(program, "chromaThreshold")
    }

    public override func setVideoFrame(_ frame: IRFFVideoFrame) {
        guard let yuvFrame = frame as? IRFFCVYUVVideoFrame else { return }
        let pixelBuffer = yuvFrame.pixelBuffer

        if videoTextureCache == nil,
           let context = EAGLContext.current() {
            var cache: CVOpenGLESTextureCache?
            let result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &cache)
            if result != kCVReturnSuccess {
                print("Error at CVOpenGLESTextureCacheCreate \(result)")
                return
            }
            videoTextureCache = cache
        }

        let frameWidth = GLsizei(frame.width)
        let frameHeight = GLsizei(frame.height)

        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)

        cleanUpTextures()

        let colorAttachments: String? = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? String
//        let colorAttachments = colorAttachments.takeUnretainedValue() as CFString
        if colorAttachments! == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String {
            preferredConversion = kIRColorConversion601
        } else {
            preferredConversion = kIRColorConversion709
        }

        var err: CVReturn

        if EAGLContext.current()?.api == .openGLES2 {
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache!,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RED_EXT,
                                                               frameWidth,
                                                               frameHeight,
                                                               GLenum(GL_RED_EXT),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               0,
                                                               &lumaTexture)
        } else {
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache!,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_LUMINANCE,
                                                               frameWidth,
                                                               frameHeight,
                                                               GLenum(GL_LUMINANCE),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               0,
                                                               &lumaTexture)
        }

        if err != kCVReturnSuccess || lumaTexture == nil {
            print("CVOpenGLESTextureCacheCreateTextureFromImage failed (error: \(err))")
            return
        }

        glBindTexture(CVOpenGLESTextureGetTarget(lumaTexture!), CVOpenGLESTextureGetName(lumaTexture!))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))

        // UV-plane
        if EAGLContext.current()?.api == .openGLES2 {
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache!,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RG_EXT,
                                                               frameWidth / 2,
                                                               frameHeight / 2,
                                                               GLenum(GL_RG_EXT),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               1,
                                                               &chromaTexture)
        } else {
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                               videoTextureCache!,
                                                               pixelBuffer,
                                                               nil,
                                                               GLenum(GL_TEXTURE_2D),
                                                               GL_RG8,
                                                               frameWidth / 2,
                                                               frameHeight / 2,
                                                               GLenum(GL_RG),
                                                               GLenum(GL_UNSIGNED_BYTE),
                                                               1,
                                                               &chromaTexture)
        }

        if err != kCVReturnSuccess {
            print("Error at CVOpenGLESTextureCacheCreateTextureFromImage \(err)")
            return
        }

        glBindTexture(CVOpenGLESTextureGetTarget(chromaTexture!), CVOpenGLESTextureGetName(chromaTexture!))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
    }

    public override func prepareRender(_ program: GLuint) -> Bool {
        resolveUniforms(program)

        guard super.prepareRender(program) else { return false }

        if lumaTexture == nil || chromaTexture == nil { return false }

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(CVOpenGLESTextureGetTarget(lumaTexture!), CVOpenGLESTextureGetName(lumaTexture!))
        glUniform1i(uniformSamplers[UniformSampler.y.rawValue], 0)

        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(CVOpenGLESTextureGetTarget(chromaTexture!), CVOpenGLESTextureGetName(chromaTexture!))
        glUniform1i(uniformSamplers[UniformSampler.uv.rawValue], 1)

        glUniformMatrix3fv(uniformParams[UniformParam.colorConversionMatrix.rawValue], 1, GLboolean(GL_FALSE), preferredConversion)
        glUniform1f(uniformParams[UniformParam.lumaThreshold.rawValue], lumaThreshold)
        glUniform1f(uniformParams[UniformParam.chromaThreshold.rawValue], chromaThreshold)

        return true
    }

    deinit {
        releaseRender()
    }

    public override func releaseRender() {
        cleanUpTextures()
        videoTextureCache = nil
    }

    private func cleanUpTextures() {
        lumaTexture = nil
        chromaTexture = nil

        if let cache = videoTextureCache {
            CVOpenGLESTextureCacheFlush(cache, 0)
        }
    }
}
