//
//  IRGLProjectionDistortion.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import OpenGLES

enum IRDistortionModelType: UInt {
    case left
    case right
}

class IRGLProjectionDistortion: IRGLProjection {
    
    func update(with parameter: IRMediaParameter) {

    }

    private(set) var modelType: IRDistortionModelType
    var index_buffer_id: GLint = 0
    var vertex_buffer_id: GLint = 0
    var index_count: Int = 0

    private var frame_buffer_id: GLuint = 0
    private var vertices: [GLfloat] = Array(repeating: 0, count: 8)
    private var bufferIDs: [GLuint] = [0, 0]

    init(modelType: IRDistortionModelType) {
        self.modelType = modelType
        setupBufferData()
    }

    deinit {
        glDeleteBuffers(2, &bufferIDs)
    }

    func updateVertex() {
        // This is where you'd update the vertex, similar to the original method
    }

    func draw() {
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(index_count), GLenum(GL_UNSIGNED_SHORT), nil)
    }

    private func setupBufferData() {
        var xEyeOffsetScreen: Float = 0.523064613
        var yEyeOffsetScreen: Float = 0.80952388
        var viewportWidthTexture: Float = 1.43138313
        var viewportHeightTexture: Float = 1.51814604
        var viewportXTexture: Float = 0
        var viewportYTexture: Float = 0
        var textureWidth: Float = 2.86276627
        var textureHeight: Float = 1.51814604
        var xEyeOffsetTexture: Float = 0.592283607
        var yEyeOffsetTexture: Float = 0.839099586
        var screenWidth: Float = 2.47470069
        var screenHeight: Float = 1.39132345

        switch modelType {
        case .left:
            break
        case .right:
            xEyeOffsetScreen = 1.95163608
            viewportXTexture = 1.43138313
            xEyeOffsetTexture = 2.27048278
        }

        var vertexData: [GLfloat] = Array(repeating: 0, count: 14400)
        var vertexOffset = 0
        let rows = 40
        let cols = 40
        let vignetteSizeTanAngle: Float = 0.05

        for row in 0..<rows {
            for col in 0..<cols {
                let uTextureBlue = Float(col) / 39.0 * (viewportWidthTexture / textureWidth) + viewportXTexture / textureWidth
                let vTextureBlue = Float(row) / 39.0 * (viewportHeightTexture / textureHeight) + viewportYTexture / textureHeight

                let xTexture = uTextureBlue * textureWidth - xEyeOffsetTexture
                let yTexture = vTextureBlue * textureHeight - yEyeOffsetTexture
                let rTexture = sqrtf(xTexture * xTexture + yTexture * yTexture)

                let textureToScreenBlue = (rTexture > 0.0) ? blueDistortInverse(radius: rTexture) / rTexture : 1.0

                let xScreen = xTexture * textureToScreenBlue
                let yScreen = yTexture * textureToScreenBlue

                let uScreen = (xScreen + xEyeOffsetScreen) / screenWidth
                let vScreen = (yScreen + yEyeOffsetScreen) / screenHeight
                let rScreen = rTexture * textureToScreenBlue

                let screenToTextureGreen = (rScreen > 0.0) ? distortionFactor(radius: rScreen) : 1.0
                let uTextureGreen = (xScreen * screenToTextureGreen + xEyeOffsetTexture) / textureWidth
                let vTextureGreen = (yScreen * screenToTextureGreen + yEyeOffsetTexture) / textureHeight

                let screenToTextureRed = (rScreen > 0.0) ? distortionFactor(radius: rScreen) : 1.0
                let uTextureRed = (xScreen * screenToTextureRed + xEyeOffsetTexture) / textureWidth
                let vTextureRed = (yScreen * screenToTextureRed + yEyeOffsetTexture) / textureHeight

                let vignetteSizeTexture = vignetteSizeTanAngle / textureToScreenBlue

                let dxTexture = clamp(value: xTexture + xEyeOffsetTexture, min: viewportXTexture + vignetteSizeTexture, max: viewportXTexture + viewportWidthTexture - vignetteSizeTexture)
                let dyTexture = clamp(value: yTexture + yEyeOffsetTexture, min: viewportYTexture + vignetteSizeTexture, max: viewportYTexture + viewportHeightTexture - vignetteSizeTexture)
                let drTexture = sqrtf(dxTexture * dxTexture + dyTexture * dyTexture)

                let vignette = 1.0 - clamp(value: drTexture / vignetteSizeTexture, min: 0.0, max: 1.0)

                vertexData[vertexOffset + 0] = 2.0 * uScreen - 1.0
                vertexData[vertexOffset + 1] = 2.0 * vScreen - 1.0
                vertexData[vertexOffset + 2] = vignette
                vertexData[vertexOffset + 3] = uTextureRed
                vertexData[vertexOffset + 4] = vTextureRed
                vertexData[vertexOffset + 5] = uTextureGreen
                vertexData[vertexOffset + 6] = vTextureGreen
                vertexData[vertexOffset + 7] = uTextureBlue
                vertexData[vertexOffset + 8] = vTextureBlue

                vertexOffset += 9
            }
        }

        index_count = 3158
        var indexData: [GLshort] = Array(repeating: 0, count: index_count)
        var indexOffset = 0
        vertexOffset = 0
        for row in 0..<(rows - 1) {
            if row > 0 {
                indexData[indexOffset] = indexData[indexOffset - 1]
                indexOffset += 1
            }
            for col in 0..<cols {
                if col > 0 {
                    if row % 2 == 0 {
                        vertexOffset += 1
                    } else {
                        vertexOffset -= 1
                    }
                }
                indexData[indexOffset] = GLshort(vertexOffset)
                indexOffset += 1
                indexData[indexOffset] = GLshort(vertexOffset + 40)
                indexOffset += 1
            }
            vertexOffset += 40
        }

        glGenBuffers(2, &bufferIDs)
        vertex_buffer_id = GLint(bufferIDs[0])
        index_buffer_id = GLint(bufferIDs[1])

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), GLuint(vertex_buffer_id))
        glBufferData(GLenum(GL_ARRAY_BUFFER), vertexData.count * MemoryLayout<GLfloat>.size, vertexData, GLenum(GL_STATIC_DRAW))

        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), GLuint(index_buffer_id))
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexData.count * MemoryLayout<GLshort>.size, indexData, GLenum(GL_STATIC_DRAW))

        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), 0)
    }

    private func blueDistortInverse(radius: Float) -> Float {
        var r0 = radius / 0.9
        var r = radius * 0.9
        var dr0 = radius - distort(radius: r0)
        while abs(r - r0) > 0.0001 {
            let dr = radius - distort(radius: r)
            let r2 = r - dr * ((r - r0) / (dr - dr0))
            r0 = r
            r = r2
            dr0 = dr
        }
        return r
    }

    private func distort(radius: Float) -> Float {
        return radius * distortionFactor(radius: radius)
    }

    private func distortionFactor(radius: Float) -> Float {
        let coefficients: [Float] = [0.441000015, 0.156000003]
        var result: Float = 1.0
        var rFactor: Float = 1.0
        let squaredRadius = radius * radius
        for coefficient in coefficients {
            rFactor *= squaredRadius
            result += coefficient * rFactor
        }
        return result
    }

    private func clamp(value: Float, min: Float, max: Float) -> Float {
        return Swift.max(min, Swift.min(max, value))
    }
}

