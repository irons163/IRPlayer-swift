//
//  IRGLProjectionOrthographic.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import OpenGLES

// Static arrays for vertex, index, and texture buffer data
let vertexBufferData: [GLKVector3] = [
    GLKVector3Make(-1, 1, 0.0),
    GLKVector3Make(1, 1, 0.0),
    GLKVector3Make(1, -1, 0.0),
    GLKVector3Make(-1, -1, 0.0)
]

let indexBufferData: [GLushort] = [
    0, 1, 2, 0, 2, 3
]

let textureBufferData: [GLKVector2] = [
    GLKVector2Make(0.0, 0.0),
    GLKVector2Make(1.0, 0.0),
    GLKVector2Make(1.0, 1.0),
    GLKVector2Make(0.0, 1.0)
]

class IRGLProjectionOrthographic: IRGLProjection {

    private var vertexBufferID: GLuint = 0
    private var indexBufferID: GLuint = 0
    private var textureBufferID: GLuint = 0

    func update(with parameter: IRMediaParameter) {

    }

    private var vertices = UnsafeMutablePointer<GLfloat>.allocate(capacity: 8)
    private var indexCount: Int = 6
    private var vertexCount: Int = 4
    private var indexID: GLuint = 0
    private var vertexID: GLuint = 0
    private var textureID: GLuint = 0

    init(textureWidth w: Float, height h: Float) {
        vertices[0] = -1.0  // x0
        vertices[1] = -1.0  // y0
        vertices[2] =  1.0  // ..
        vertices[3] = -1.0
        vertices[4] = -1.0
        vertices[5] =  1.0
        vertices[6] =  1.0  // x3
        vertices[7] =  1.0  // y3

        glGenBuffers(1, &indexBufferID)
        glGenBuffers(1, &vertexBufferID)
        glGenBuffers(1, &textureBufferID)
    }

    deinit {
        glDeleteBuffers(1, &indexBufferID)
        glDeleteBuffers(1, &vertexBufferID)
        glDeleteBuffers(1, &textureBufferID)
    }

    func updateVertex() {
        bindPositionLocation(GLint(Attribute.vertex.rawValue), textureCoordLocation: GLint(Attribute.texcoord.rawValue))
    }

    func draw() {
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(indexCount), GLenum(GL_UNSIGNED_SHORT), nil)
    }
}

extension IRGLProjectionOrthographic {

    private func bindPositionLocation(_ positionLocation: GLint, textureCoordLocation: GLint) {
        // index
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBufferID)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), GLsizeiptr(indexCount * MemoryLayout<GLushort>.size), indexBufferData, GLenum(GL_STATIC_DRAW))

        // vertex
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBufferID)
        glBufferData(GLenum(GL_ARRAY_BUFFER), GLsizeiptr(vertexCount * 3 * MemoryLayout<GLfloat>.size), vertexBufferData, GLenum(GL_STATIC_DRAW))
        glEnableVertexAttribArray(GLuint(positionLocation))
        glVertexAttribPointer(GLuint(positionLocation), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(3 * MemoryLayout<GLfloat>.size), nil)

        // texture coord
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), textureBufferID)
        glBufferData(GLenum(GL_ARRAY_BUFFER), GLsizeiptr(vertexCount * 2 * MemoryLayout<GLfloat>.size), textureBufferData, GLenum(GL_DYNAMIC_DRAW))
        glEnableVertexAttribArray(GLuint(textureCoordLocation))
        glVertexAttribPointer(GLuint(textureCoordLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2 * MemoryLayout<GLfloat>.size), nil)
    }
}
