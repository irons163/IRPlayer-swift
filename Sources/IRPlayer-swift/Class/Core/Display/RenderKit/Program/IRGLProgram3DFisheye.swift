//
//  IRGLProgram3DFisheye.swift
//  IRPlayer-swift
//
//  Metal-only implementation (OpenGL-free)
//

import Foundation

@objcMembers public class IRGLProgram3DFisheye: IRGLProgram2D {

    public override func didUpdateOutputWH(_ w: Int, _ h: Int) {
        guard let parameter = parameter,
              parameter.autoUpdate,
              (Float(w) != parameter.width || Float(h) != parameter.height) else {
            return
        }

        parameter.width = Float(w)
        parameter.height = Float(h)
        mapProjection?.update(with: parameter)
    }

    public override func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            return false
        }
        return true
    }
}
