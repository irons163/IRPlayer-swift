//
//  IRGLRenderRGB.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/18.
//

import Foundation
import OpenGLES

@objcMembers public class IRGLRenderRGB: IRGLRenderBase {
    private var uniformSampler: GLint = 0
    private var texture: GLuint = 0

    public override func isValid() -> Bool {
        return texture != 0
    }

    public override func resolveUniforms(_ program: GLuint) {
        super.resolveUniforms(program)
        uniformSampler = glGetUniformLocation(program, "s_texture")
    }

    public override func setVideoFrame(_ frame: IRFFVideoFrame) {
        guard let rgbFrame = frame as? IRVideoFrameRGB else {
            return
        }

        assert(rgbFrame.rgb.count == rgbFrame.width * rgbFrame.height * 3)

        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)

        if texture == 0 {
            glGenTextures(1, &texture)
        }

        glBindTexture(GLenum(GL_TEXTURE_2D), texture)

        glTexImage2D(GLenum(GL_TEXTURE_2D),
                     0,
                     GL_RGB,
                     GLsizei(frame.width),
                     GLsizei(frame.height),
                     0,
                     GLenum(GL_RGB),
                     GLenum(GL_UNSIGNED_BYTE),
                     rgbFrame.rgb.withUnsafeBytes { $0.baseAddress })

        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
    }

    public override func prepareRender(_ program: GLuint) -> Bool {
        guard super.prepareRender(program) else {
            return false
        }

        if texture == 0 {
            return false
        }

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glUniform1i(uniformSampler, 0)

        return true
    }

    deinit {
        releaseRender()
    }

    public override func releaseRender() {
        if texture != 0 {
            glDeleteTextures(1, &texture)
            texture = 0
        }
    }
}
