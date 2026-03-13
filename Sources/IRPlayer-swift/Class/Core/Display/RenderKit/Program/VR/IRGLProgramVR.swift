//
//  IRGLProgramVR.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgramVR: IRGLProgram2D {

    private var initialDefaultScale: Float?

    override func setDefaultScale(_ scale: Float) {
        super.setDefaultScale(scale)
        if initialDefaultScale == nil {
            initialDefaultScale = scale
        }
    }

    override func didDoubleTap() {
        if let scale = initialDefaultScale,
           let controller = tramsformController as? IRGLTransformController3DFisheye {
            controller.update(fx: 0, fy: 0, sx: scale, sy: scale)
            return
        }
        super.didDoubleTap()
    }

    public override func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            return false
        }
        return true
    }
}
