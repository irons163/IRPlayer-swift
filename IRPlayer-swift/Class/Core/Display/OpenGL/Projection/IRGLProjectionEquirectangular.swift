//
//  IRGLProjectionEquirectangular.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import OpenGLES

let SPHERE_RADIUS: Float = 800.0
let SPHERE_SLICES = 180
let SPHERE_INDICES_PER_VERTEX = 1
let POLAR_LAT: Float = 85.0

class IRGLProjectionEquirectangular: IRGLProjection {

    static var vertexBufferID: GLuint = 0
    static var indexBufferID: GLuint = 0
    static var textureBufferID: GLuint = 0

    private var mIndices: UnsafeMutablePointer<UnsafeMutablePointer<Int16>>?
    private var slices: Int = SPHERE_SLICES
    private var mVertices: UnsafeMutablePointer<Float>?
    private var mVectors: UnsafeMutablePointer<Float>?
    private var mTotalIndices: Int = 0
    private var nVertices: Int = 0
    private var indicesPerVertex: Int = SPHERE_INDICES_PER_VERTEX
    private var mNumIndices: UnsafeMutablePointer<Int>?
    private var x0: Float = 0
    private var y0: Float = 0
    private var z0: Float = 0
    private var r0: Float = SPHERE_RADIUS
    private var tw: Float = 0
    private var th: Float = 0
    private var cr: Float = 0
    private var cx: Float = 0
    private var cy: Float = 0

    init(textureWidth w: Float, height h: Float, centerX: Float, centerY: Float, radius: Float) {
        setup(textureWidth: w, height: h, centerX: centerX, centerY: centerY, radius: radius)
        glGenBuffers(1, &IRGLProjectionEquirectangular.indexBufferID)
        glGenBuffers(1, &IRGLProjectionEquirectangular.vertexBufferID)
        glGenBuffers(1, &IRGLProjectionEquirectangular.textureBufferID)
    }

    private func setup(textureWidth w: Float, height h: Float, centerX: Float, centerY: Float, radius: Float) {
        x0 = 0
        y0 = 0
        z0 = 0
        r0 = SPHERE_RADIUS
        slices = SPHERE_SLICES
        indicesPerVertex = SPHERE_INDICES_PER_VERTEX
        tw = w
        th = h

        var radius = radius
        var centerX = centerX
        var centerY = centerY

        if radius == 0 || centerX == 0 || centerY == 0 || radius > w / 2 || radius > h / 2 ||
            radius + centerX > w || radius + centerY > h {
            print("illegal params, set default ones...")
            centerX = w / 2
            centerY = h / 2
            radius = min(w, h) / 2
        }

        cr = radius
        cx = centerX
        cy = centerY

        initBuffers(tw: tw, th: th, cr: cr, cx: cx, cy: cy)
    }

    private func initBuffers(tw: Float, th: Float, cr: Float, cx: Float, cy: Float) {
        if cr <= 0 || cx <= 0 || cy <= 0 || tw < cr || th < cr || cx + cr > tw || cy + cr > th {
            print("illegal params")
            return
        }

        let iMax = slices + 1
        nVertices = iMax * iMax
        guard nVertices <= Int.max else {
            print("nSlices \(slices) too big for vertex")
            return
        }

        mVertices = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        mVectors = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 2)
        mTotalIndices = slices * slices * 6
        mIndices = UnsafeMutablePointer<UnsafeMutablePointer<Int16>>.allocate(capacity: indicesPerVertex)
        mNumIndices = UnsafeMutablePointer<Int>.allocate(capacity: indicesPerVertex)

        let noIndicesPerBuffer = (mTotalIndices / indicesPerVertex / 6) * 6
        for i in 0..<indicesPerVertex - 1 {
            mNumIndices?[i] = noIndicesPerBuffer
        }
        mNumIndices?[indicesPerVertex - 1] = mTotalIndices - noIndicesPerBuffer * (indicesPerVertex - 1)

        for i in 0..<indicesPerVertex {
            mIndices?[i] = UnsafeMutablePointer<Int16>.allocate(capacity: mNumIndices?[i] ?? 0)
        }

        var mVerticesPosition: Int = 0
        var mVectorsPosition: Int = 0
        var vLineBuffer = [Float](repeating: 0, count: iMax * 3)
        var vLineBuffer2 = [Float](repeating: 0, count: iMax * 2)
        let angleStep: Float = Float.pi / Float(slices)

        for i in 0..<iMax {
            let sini = sin(angleStep * Float(i))
            let cosi = cos(angleStep * Float(i))
            for j in 0..<iMax {
                let vertexBase = j * 3
                let vectorBase = (iMax - j - 1) * 2
                let sinisinj = sin(angleStep * Float(j)) * sini
                let sinicosj = cos(angleStep * Float(j)) * sini

                // vertex x, y, z
                vLineBuffer[vertexBase] = x0 + r0 * sinisinj
                vLineBuffer[vertexBase + 1] = y0 + r0 * sinicosj
                vLineBuffer[vertexBase + 2] = z0 + r0 * cosi

                vLineBuffer2[vectorBase] = (cx - cr * sinicosj) / tw
                vLineBuffer2[vectorBase + 1] = (cr * cosi - cy) / th
            }

            let mVerticesLength = Int(vLineBuffer.count * MemoryLayout<Float>.size)
            let mVectorsLength = Int(vLineBuffer2.count * MemoryLayout<Float>.size)
            memcpy(mVertices?.advanced(by: (Int(mVerticesPosition)/MemoryLayout<Float>.size)), vLineBuffer, Int(mVerticesLength))
            memcpy(mVectors?.advanced(by: (Int(mVectorsPosition)/MemoryLayout<Float>.size)), vLineBuffer2, Int(mVectorsLength))
            mVerticesPosition += mVerticesLength
            mVectorsPosition += mVectorsLength
        }

        let indexBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: getMaxItem(array: mNumIndices, size: indicesPerVertex))
        var index = 0
        var bufferNum = 0

        for i in 0..<slices {
            let i1 = i + 1
            for j in 0..<slices {
                let j1 = j + 1
                if index >= mNumIndices?[bufferNum] ?? 0 {
                    memcpy(mIndices?[bufferNum], indexBuffer, Int((mNumIndices?[bufferNum] ?? 0) * MemoryLayout<Int16>.size))
                    index = 0
                    bufferNum += 1
                }
                indexBuffer[index] = Int16(i * iMax + j)
                index += 1
                indexBuffer[index] = Int16(i1 * iMax + j)
                index += 1
                indexBuffer[index] = Int16(i1 * iMax + j1)
                index += 1
                indexBuffer[index] = Int16(i * iMax + j)
                index += 1
                indexBuffer[index] = Int16(i1 * iMax + j1)
                index += 1
                indexBuffer[index] = Int16(i * iMax + j1)
                index += 1
            }
        }

        memcpy(mIndices?[bufferNum], indexBuffer, (mNumIndices?[bufferNum] ?? 0) * MemoryLayout<Int16>.size)
        free(indexBuffer)
    }

    private func getMaxItem(array: UnsafeMutablePointer<Int>?, size: Int) -> Int {
        var max = array?[0] ?? 0
        for i in 1..<size {
            if array?[i] ?? 0 > max {
                max = array?[i] ?? 0
            }
        }
        return max
    }

    func updateVertex() {
//        glVertexAttribPointer(GLuint(Attribute.vertex.rawValue), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mVertices)
//        glEnableVertexAttribArray(GLuint(Attribute.vertex.rawValue))
//        glVertexAttribPointer(GLuint(Attribute.texcoord.rawValue), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mVectors)
//        glEnableVertexAttribArray(GLuint(Attribute.texcoord.rawValue))
//        glGenBuffers(1, &IRGLProjectionEquirectangular.indexBufferID)
//        glGenBuffers(1, &IRGLProjectionEquirectangular.vertexBufferID)
//        glGenBuffers(1, &IRGLProjectionEquirectangular.textureBufferID)
//        IRGLProjectionEquirectangular.genQQQ
        bindPositionLocation(GLint(Attribute.vertex.rawValue), textureCoordLocation: GLint(Attribute.texcoord.rawValue))
    }

    func bindPositionLocation(_ positionLocation: GLint, textureCoordLocation: GLint) {
        // index
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), IRGLProjectionEquirectangular.indexBufferID)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), GLsizeiptr(mTotalIndices * MemoryLayout<GLushort>.size), mIndices?[0], GLenum(GL_STATIC_DRAW))

        // vertex
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), IRGLProjectionEquirectangular.vertexBufferID)
        glBufferData(GLenum(GL_ARRAY_BUFFER), GLsizeiptr(nVertices * 3 * MemoryLayout<GLfloat>.size), mVertices, GLenum(GL_STATIC_DRAW))
        glEnableVertexAttribArray(GLuint(positionLocation))
        glVertexAttribPointer(GLuint(positionLocation), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(3 * MemoryLayout<GLfloat>.size), nil)

        // texture coord
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), IRGLProjectionEquirectangular.textureBufferID)
        glBufferData(GLenum(GL_ARRAY_BUFFER), GLsizeiptr(nVertices * 2 * MemoryLayout<GLfloat>.size), mVectors, GLenum(GL_DYNAMIC_DRAW))
        glEnableVertexAttribArray(GLuint(textureCoordLocation))
        glVertexAttribPointer(GLuint(textureCoordLocation), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(2 * MemoryLayout<GLfloat>.size), nil)
    }

    func draw() {
        for j in 0..<indicesPerVertex {
            glDrawElements(GLenum(GL_TRIANGLES), GLsizei(mNumIndices?[j] ?? 0), GLenum(GL_UNSIGNED_SHORT), nil)
        }
//        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(mTotalIndices), GLenum(GL_UNSIGNED_SHORT), nil)
    }

    func update(with parameter: IRMediaParameter) {
        if let p = parameter as? IRFisheyeParameter {
            if tw == p.width && th == p.height { return }
            setup(textureWidth: p.width, height: p.height, centerX: p.cx, centerY: p.cy, radius: p.rx)
        }
    }

    deinit {
        for i in 0..<indicesPerVertex {
            free(mIndices?[i])
        }
        free(mIndices)
        free(mVertices)
        free(mVectors)
        free(mNumIndices)
        glDeleteBuffers(1, &IRGLProjectionEquirectangular.indexBufferID)
        glDeleteBuffers(1, &IRGLProjectionEquirectangular.vertexBufferID)
        glDeleteBuffers(1, &IRGLProjectionEquirectangular.textureBufferID)
    }
}
