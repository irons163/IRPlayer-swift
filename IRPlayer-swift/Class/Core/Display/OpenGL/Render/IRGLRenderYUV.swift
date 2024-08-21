//
//  IRGLRenderYUV.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/18.
//

import Foundation
import OpenGLES

@objcMembers public class IRGLRenderYUV: IRGLRenderBase {

    private var uniformSamplers = [GLint](repeating: 0, count: 3)
    private var textures = [GLuint](repeating: 0, count: 3)
    private var uniformParams = [GLint](repeating: 0, count: 1)
    private var preferredConversion: [GLfloat] = kIRColorConversion709

    public override init() {
        super.init()
        self.preferredConversion = kIRColorConversion709
    }

    public override func isValid() -> Bool {
        return textures[0] != 0
    }

    public override func resolveUniforms(_ program: GLuint) {
        super.resolveUniforms(program)

        uniformSamplers[0] = glGetUniformLocation(program, "s_texture_y")
        uniformSamplers[1] = glGetUniformLocation(program, "s_texture_u")
        uniformSamplers[2] = glGetUniformLocation(program, "s_texture_v")

        uniformParams[0] = glGetUniformLocation(program, "colorConversionMatrix")
    }

    public override func setVideoFrame(_ frame: IRFFVideoFrame) {
        guard let yuvFrame = frame as? IRFFAVYUVVideoFrame else { return }

        let frameWidth = GLsizei(frame.width)
        let frameHeight = GLsizei(frame.height)

        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)

        var isFirst = false
        if textures[0] == 0 {
            isFirst = true
            glGenTextures(3, &textures)
        }

        let pixels: [UnsafeMutablePointer<UInt8>?] = [yuvFrame.luma, yuvFrame.chromaB, yuvFrame.chromaR]
        let widths: [GLsizei] = [frameWidth, frameWidth / 2, frameWidth / 2]
        let heights: [GLsizei] = [frameHeight, frameHeight / 2, frameHeight / 2]

        for i in 0..<3 {
            glBindTexture(GLenum(GL_TEXTURE_2D), textures[i])

            if isFirst {
                glTexImage2D(GLenum(GL_TEXTURE_2D),
                             0,
                             GL_LUMINANCE,
                             widths[i],
                             heights[i],
                             0,
                             GLenum(GL_LUMINANCE),
                             GLenum(GL_UNSIGNED_BYTE),
                             pixels[i])

                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
            } else {
                glTexSubImage2D(GLenum(GL_TEXTURE_2D),
                                0,
                                0,
                                0,
                                widths[i],
                                heights[i],
                                GLenum(GL_LUMINANCE),
                                GLenum(GL_UNSIGNED_BYTE),
                                pixels[i])
            }
        }
    }

    public override func prepareRender(_ program: GLuint) -> Bool {
        guard super.prepareRender(program) else { return false }

        if textures[0] == 0 {
            return false
        }

        for i in 0..<3 {
            glActiveTexture(GLenum(Int(GL_TEXTURE0) + i))
            glBindTexture(GLenum(GL_TEXTURE_2D), textures[i])
            glUniform1i(uniformSamplers[i], GLint(i))
        }

        glUniformMatrix3fv(uniformParams[0], 1, GLboolean(GL_FALSE), preferredConversion)

        return true
    }

    deinit {
        releaseRender()
    }

    public override func releaseRender() {
        if textures[0] != 0 {
            glDeleteTextures(3, &textures)
            textures[0] = 0
        }
    }
}
