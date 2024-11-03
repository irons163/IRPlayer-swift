//
//  IRGLProjectionVR.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import OpenGLES

class IRGLProjectionVR: IRGLProjection {

    var index_id: GLuint = 0
    var vertex_id: GLuint = 0
    var texture_id: GLuint = 0

    var index_count: Int = 0
    var vertex_count: Int = 0

    // Static properties and functions
    private static var vertex_buffer_id: GLuint = 0
    private static var index_buffer_id: GLuint = 0
    private static var texture_buffer_id: GLuint = 0

    private static var vertex_buffer_data: UnsafeMutablePointer<GLfloat>? = nil
    private static var index_buffer_data: UnsafeMutablePointer<GLushort>? = nil
    private static var texture_buffer_data: UnsafeMutablePointer<GLfloat>? = nil

    private static let slices_count = 200
    private static let parallels_count = slices_count / 2

    private static let index_count = slices_count * parallels_count * 6
    private static let vertex_count = (slices_count + 1) * (parallels_count + 1)

    init(textureWidth w: Float, height h: Float) {
        setupModel()
    }

    func update(with parameter: IRMediaParameter) {

    }

    func updateVertex() {
        bindPositionLocation(position_location: GLint(Attribute.vertex.rawValue), textureCoordLocation: GLint(Attribute.texcoord.rawValue))
    }

    func draw() {
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(index_count), GLenum(GL_UNSIGNED_SHORT), nil)
    }
}

extension IRGLProjectionVR {

    private func setupModel() {
        setupVR()
        index_count = IRGLProjectionVR.index_count
        vertex_count = IRGLProjectionVR.vertex_count
        index_id = IRGLProjectionVR.index_buffer_id
        vertex_id = IRGLProjectionVR.vertex_buffer_id
        texture_id = IRGLProjectionVR.texture_buffer_id
    }

    private func setupVR() {
        let step: Float = (2.0 * .pi) / Float(IRGLProjectionVR.slices_count)
        let radius: Float = 1.0

        // Model
        IRGLProjectionVR.index_buffer_data = UnsafeMutablePointer<GLushort>.allocate(capacity: IRGLProjectionVR.index_count)
        IRGLProjectionVR.vertex_buffer_data = UnsafeMutablePointer<GLfloat>.allocate(capacity: IRGLProjectionVR.vertex_count * 3)
        IRGLProjectionVR.texture_buffer_data = UnsafeMutablePointer<GLfloat>.allocate(capacity: IRGLProjectionVR.vertex_count * 2)

        var runCount = 0
        for i in 0...IRGLProjectionVR.parallels_count {
            for j in 0...IRGLProjectionVR.slices_count {
                let vertex = (i * (IRGLProjectionVR.slices_count + 1) + j) * 3

                // Vertex data
                IRGLProjectionVR.vertex_buffer_data?[vertex] = radius * sinf(step * Float(i)) * cosf(step * Float(j))
                IRGLProjectionVR.vertex_buffer_data?[vertex + 1] = radius * cosf(step * Float(i))
                IRGLProjectionVR.vertex_buffer_data?[vertex + 2] = radius * sinf(step * Float(i)) * sinf(step * Float(j))

                // Texture data
                let textureIndex = (i * (IRGLProjectionVR.slices_count + 1) + j) * 2
                IRGLProjectionVR.texture_buffer_data?[textureIndex] = Float(j) / Float(IRGLProjectionVR.slices_count)
                IRGLProjectionVR.texture_buffer_data?[textureIndex + 1] = Float(i) / Float(IRGLProjectionVR.parallels_count)

                // Index data
                if i < IRGLProjectionVR.parallels_count && j < IRGLProjectionVR.slices_count {
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort(i * (IRGLProjectionVR.slices_count + 1) + j)
                    runCount += 1
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort((i + 1) * (IRGLProjectionVR.slices_count + 1) + j)
                    runCount += 1
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort((i + 1) * (IRGLProjectionVR.slices_count + 1) + (j + 1))
                    runCount += 1
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort(i * (IRGLProjectionVR.slices_count + 1) + j)
                    runCount += 1
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort((i + 1) * (IRGLProjectionVR.slices_count + 1) + (j + 1))
                    runCount += 1
                    IRGLProjectionVR.index_buffer_data?[runCount] = GLushort(i * (IRGLProjectionVR.slices_count + 1) + (j + 1))
                    runCount += 1
                }
            }
        }

        glGenBuffers(1, &IRGLProjectionVR.index_buffer_id)
        glGenBuffers(1, &IRGLProjectionVR.vertex_buffer_id)
        glGenBuffers(1, &IRGLProjectionVR.texture_buffer_id)
    }

    private func bindPositionLocation(position_location: GLint, textureCoordLocation: GLint) {
        // Index
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), index_id)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), index_count * MemoryLayout<GLushort>.size, IRGLProjectionVR.index_buffer_data, GLenum(GL_STATIC_DRAW))

        // Vertex
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertex_id)
        glBufferData(GLenum(GL_ARRAY_BUFFER), vertex_count * 3 * MemoryLayout<GLfloat>.size, IRGLProjectionVR.vertex_buffer_data, GLenum(GL_STATIC_DRAW))
        glEnableVertexAttribArray(GLuint(position_location))
        glVertexAttribPointer(GLuint(position_location), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(3 * MemoryLayout<GLfloat>.size), nil)

        // Texture coord
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), texture_id)
        glBufferData(GLenum(GL_ARRAY_BUFFER), vertex_count * 2 * MemoryLayout<GLfloat>.size, IRGLProjectionVR.texture_buffer_data, GLenum(GL_DYNAMIC_DRAW))
        glEnableVertexAttribArray(GLuint(textureCoordLocation))
        glVertexAttribPointer(GLuint(textureCoordLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2 * MemoryLayout<GLfloat>.size), nil)
    }
}
