//
//  IRGLMath.swift
//  IRPlayer-swift
//
//  Metal-only math helpers (OpenGL-free)
//

import Foundation
import simd

// OpenGL typealiases retained for API compatibility
public typealias GLfloat = Float
public typealias GLint = Int32
public typealias GLuint = UInt32
public typealias GLushort = UInt16
public typealias GLenum = UInt32
public typealias GLsizei = Int32

enum IRMatrix4 {
    static func identity() -> simd_float4x4 {
        matrix_identity_float4x4
    }

    static func makeTranslation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(x, y, z, 1)
        ))
    }

    static func makeScale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func makeRotation(_ radians: Float, _ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        let axis = simd_normalize(SIMD3<Float>(x, y, z))
        let ct = cos(radians)
        let st = sin(radians)
        let ci = 1 - ct
        let x = axis.x, y = axis.y, z = axis.z

        return simd_float4x4(columns: (
            SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
            SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
            SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func makePerspective(_ fovyRadians: Float, _ aspect: Float, _ near: Float, _ far: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)

        return simd_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, near * zs, 0)
        ))
    }

    static func makeLookAt(_ eye: SIMD3<Float>, _ center: SIMD3<Float>, _ up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)

        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    static func makeOrtho(_ left: Float, _ right: Float, _ bottom: Float, _ top: Float, _ near: Float, _ far: Float) -> simd_float4x4 {
        let rml = right - left
        let tmb = top - bottom
        let fmn = far - near
        return simd_float4x4(columns: (
            SIMD4<Float>(2 / rml, 0, 0, 0),
            SIMD4<Float>(0, 2 / tmb, 0, 0),
            SIMD4<Float>(0, 0, -2 / fmn, 0),
            SIMD4<Float>(-(right + left) / rml, -(top + bottom) / tmb, -(far + near) / fmn, 1)
        ))
    }

    static func multiply(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 {
        simd_mul(a, b)
    }
}

extension simd_float4x4 {
    func toMetalClipSpace() -> simd_float4x4 {
        let clip = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 0.5, 0),
            SIMD4<Float>(0, 0, 0.5, 1)
        ))
        return simd_mul(clip, self)
    }
}
