//
//  IRGLProgramDistortion.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgramDistortion: IRGLProgram2D {

    var transformControllerDistortion: IRGLTransformControllerDistortion? {
        return transformController as? IRGLTransformControllerDistortion
    }

    public override init(pixelFormat: IRPixelFormat, viewportRange: CGRect, parameter: IRMediaParameter?) {
        super.init(pixelFormat: pixelFormat, viewportRange: viewportRange, parameter: parameter)
    }

    override func setViewportRange(_ viewportRange: CGRect, resetTransform: Bool) {
        super.setViewportRange(viewportRange, resetTransform: resetTransform)
        guard let viewportSize = Self.viewportSize(from: viewportRange) else { return }
        transformControllerDistortion?.resetViewport(width: viewportSize.width / 2,
                                                    height: viewportSize.height,
                                                    resetTransform: false)
    }

    public override func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            return false
        }
        return true
    }
}
