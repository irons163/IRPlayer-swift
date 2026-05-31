//
//  IRGLProjectionEquirectangular.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation
import simd

let SPHERE_RADIUS: Float = 800.0
let SPHERE_SLICES = 180
let SPHERE_INDICES_PER_VERTEX = 1
let POLAR_LAT: Float = 85.0

class IRGLProjectionEquirectangular: IRGLProjection {

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

    struct BufferPlan {
        let iMax: Int
        let vertexCount: Int
        let vertexCapacity: Int
        let vectorCapacity: Int
        let totalIndices: Int
    }

    init(textureWidth w: Float, height h: Float, centerX: Float, centerY: Float, radius: Float) {
        setup(textureWidth: w, height: h, centerX: centerX, centerY: centerY, radius: radius)
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
            return
        }

        guard let plan = Self.bufferPlan(slices: slices, indicesPerVertex: indicesPerVertex) else { return }
        releaseBuffers()

        let iMax = plan.iMax
        nVertices = plan.vertexCount
        mVertices = UnsafeMutablePointer<Float>.allocate(capacity: plan.vertexCapacity)
        mVectors = UnsafeMutablePointer<Float>.allocate(capacity: plan.vectorCapacity)
        mTotalIndices = plan.totalIndices
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

                vLineBuffer[vertexBase] = x0 + r0 * sinisinj
                vLineBuffer[vertexBase + 1] = y0 + r0 * sinicosj
                vLineBuffer[vertexBase + 2] = z0 + r0 * cosi

                vLineBuffer2[vectorBase] = (cx - cr * sinicosj) / tw
                vLineBuffer2[vectorBase + 1] = (cr * cosi - cy) / th
            }

            guard let mVerticesLength = Self.byteCount(elementCount: vLineBuffer.count, stride: MemoryLayout<Float>.size),
                  let mVectorsLength = Self.byteCount(elementCount: vLineBuffer2.count, stride: MemoryLayout<Float>.size) else {
                releaseBuffers()
                return
            }
            memcpy(mVertices?.advanced(by: (mVerticesPosition / MemoryLayout<Float>.size)), vLineBuffer, mVerticesLength)
            memcpy(mVectors?.advanced(by: (mVectorsPosition / MemoryLayout<Float>.size)), vLineBuffer2, mVectorsLength)
            mVerticesPosition += mVerticesLength
            mVectorsPosition += mVectorsLength
        }

        guard let maxIndexCount = Self.maxItem(in: mNumIndices, size: indicesPerVertex) else {
            releaseBuffers()
            return
        }
        let indexBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: maxIndexCount)
        defer { indexBuffer.deallocate() }
        var index = 0
        var bufferNum = 0

        for i in 0..<slices {
            let i1 = i + 1
            for j in 0..<slices {
                let j1 = j + 1
                if index >= mNumIndices?[bufferNum] ?? 0 {
                    guard let indexByteCount = Self.byteCount(elementCount: mNumIndices?[bufferNum] ?? 0, stride: MemoryLayout<Int16>.size) else {
                        releaseBuffers()
                        return
                    }
                    memcpy(mIndices?[bufferNum], indexBuffer, indexByteCount)
                    index = 0
                    bufferNum += 1
                }
                guard let first = Self.indexValue(i * iMax + j),
                      let second = Self.indexValue(i1 * iMax + j),
                      let third = Self.indexValue(i1 * iMax + j1),
                      let fourth = Self.indexValue(i * iMax + j1) else {
                    releaseBuffers()
                    return
                }
                indexBuffer[index] = first
                index += 1
                indexBuffer[index] = second
                index += 1
                indexBuffer[index] = third
                index += 1
                indexBuffer[index] = first
                index += 1
                indexBuffer[index] = third
                index += 1
                indexBuffer[index] = fourth
                index += 1
            }
        }

        guard let indexByteCount = Self.byteCount(elementCount: mNumIndices?[bufferNum] ?? 0, stride: MemoryLayout<Int16>.size) else {
            releaseBuffers()
            return
        }
        memcpy(mIndices?[bufferNum], indexBuffer, indexByteCount)
    }

    static func maxItem(in array: UnsafeMutablePointer<Int>?, size: Int) -> Int? {
        guard let array, size > 0 else { return nil }
        var max = array[0]
        for i in 1..<size {
            if array[i] > max {
                max = array[i]
            }
        }
        return max
    }

    func update(with parameter: IRMediaParameter) {
        if let p = parameter as? IRFisheyeParameter {
            setup(textureWidth: p.width, height: p.height, centerX: p.cx, centerY: p.cy, radius: p.rx)
        }
    }

    func updateVertex() {
        // No-op for Metal
    }

    func draw() {
        // No-op for Metal
    }

    deinit {
        releaseBuffers()
    }

    private func releaseBuffers() {
        if let mIndices {
            for i in 0..<indicesPerVertex {
                mIndices[i].deallocate()
            }
            mIndices.deallocate()
        }
        mVertices?.deallocate()
        mVectors?.deallocate()
        mNumIndices?.deallocate()

        mIndices = nil
        mVertices = nil
        mVectors = nil
        mNumIndices = nil
    }

    func exportMesh() -> (positions: [SIMD3<Float>], texcoords: [SIMD2<Float>], indices: [UInt16])? {
        guard let mVertices = mVertices,
              let mVectors = mVectors,
              let mIndices = mIndices,
              let mNumIndices = mNumIndices else { return nil }

        let count = nVertices
        var positions = [SIMD3<Float>]()
        var texcoords = [SIMD2<Float>]()
        positions.reserveCapacity(count)
        texcoords.reserveCapacity(count)

        for i in 0..<count {
            let vBase = i * 3
            let tBase = i * 2
            positions.append(SIMD3<Float>(mVertices[vBase], mVertices[vBase + 1], mVertices[vBase + 2]))
            texcoords.append(SIMD2<Float>(mVectors[tBase], mVectors[tBase + 1]))
        }

        let indexCount = mNumIndices[0]
        var indices = [UInt16]()
        indices.reserveCapacity(indexCount)
        let indexPtr = mIndices[0]
        for i in 0..<indexCount {
            indices.append(UInt16(bitPattern: indexPtr[i]))
        }

        return (positions, texcoords, indices)
    }

    static func bufferPlan(slices: Int, indicesPerVertex: Int) -> BufferPlan? {
        guard slices > 0, indicesPerVertex > 0 else { return nil }

        let (iMax, iMaxOverflow) = slices.addingReportingOverflow(1)
        guard !iMaxOverflow else { return nil }

        guard let vertexCount = elementCount(baseCount: iMax, components: iMax),
              let vertexCapacity = elementCount(baseCount: vertexCount, components: 3),
              let vectorCapacity = elementCount(baseCount: vertexCount, components: 2),
              let sliceSquareCount = elementCount(baseCount: slices, components: slices),
              let totalIndices = elementCount(baseCount: sliceSquareCount, components: 6) else {
            return nil
        }

        return BufferPlan(iMax: iMax,
                          vertexCount: vertexCount,
                          vertexCapacity: vertexCapacity,
                          vectorCapacity: vectorCapacity,
                          totalIndices: totalIndices)
    }

    static func elementCount(baseCount: Int, components: Int) -> Int? {
        guard baseCount > 0, components > 0 else { return nil }

        let (count, overflow) = baseCount.multipliedReportingOverflow(by: components)
        guard !overflow, count > 0 else { return nil }

        return count
    }

    static func byteCount(elementCount: Int, stride: Int) -> Int? {
        guard elementCount > 0, stride > 0 else { return nil }

        let (count, overflow) = elementCount.multipliedReportingOverflow(by: stride)
        guard !overflow, count > 0 else { return nil }

        return count
    }

    static func indexValue(_ value: Int) -> Int16? {
        guard value >= Int(Int16.min), value <= Int(Int16.max) else { return nil }
        return Int16(value)
    }
}
