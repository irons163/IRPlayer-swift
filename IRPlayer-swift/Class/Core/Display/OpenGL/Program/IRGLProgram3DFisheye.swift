//
//  IRGLProgram3DFisheye.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/23.
//

import Foundation

@objcMembers public class IRGLProgram3DFisheye: IRGLProgram2D {

    override func vertexShader() -> String {
        let vertexShaderString = IRGLVertex3DShaderGLSL.getShardString()
        return vertexShaderString
    }

    override func fragmentShader() -> String {
        var fragmentShaderString: String
        switch pixelFormat {
        case .RGB_IRPixelFormat:
            fragmentShaderString = IRGLFragmentRGBShaderGLSL.getShardString()
        case .YUV_IRPixelFormat:
            fragmentShaderString = IRGLFragmentYUVShaderGLSL.getShardString()
        case .NV12_IRPixelFormat:
            fragmentShaderString = IRGLFragmentNV12ShaderGLSL.getShardString()
        @unknown default:
            fragmentShaderString = ""
            break
        }
        return fragmentShaderString
    }

    public override func didUpdateOutputWH(_ w: Int32, _ h: Int32) {
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
