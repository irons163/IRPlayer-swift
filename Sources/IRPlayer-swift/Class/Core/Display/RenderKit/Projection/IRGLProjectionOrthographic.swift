//
//  IRGLProjectionOrthographic.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

final class IRGLProjectionOrthographic: IRGLProjection {
    init(textureWidth _: Float, height _: Float) {}

    // Flat quads are supplied by the Metal renderer, independent of media size.
    func update(with _: IRMediaParameter) {}
}
