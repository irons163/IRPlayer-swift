//
//  IRGLProjectionOrthographic.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

class IRGLProjectionOrthographic: IRGLProjection {

    init(textureWidth w: Float, height h: Float) {
        // No OpenGL buffer setup needed for Metal path.
    }

    func update(with parameter: IRMediaParameter) {
        // No-op
    }

    func updateVertex() {
        // No-op
    }

    func draw() {
        // No-op
    }
}
