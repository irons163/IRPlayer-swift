//
//  IRGLProgramVR.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/8/26.
//

import GLKit

@objcMembers public class IRGLProgramVR: IRGLProgram2D {

    var indexId: GLuint = 0
    var vertexId: GLuint = 0
    var textureId: GLuint = 0

    var indexCount: Int = 0
    var vertexCount: Int = 0

    override func vertexShader() -> String {
        let vertexShaderString = IRGLVertexShaderGLSL.getShardString()
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
        }
        return fragmentShaderString
    }

    public override func doScrollVertical(status: IRGLTransformController.ScrollStatus, transformController: IRGLTransformController) -> Bool {
        if status.contains(.toMaxY) || status.contains(.toMinY) {
            return false
        }
        return true
    }

    /*
    override func loadShaders() -> Bool {
        if super.loadShaders() {
            fish2Pano.resolveUniforms(program)
            return true
        }
        return false
    }

    override func setRenderFrame(_ frame: IRFFVideoFrame) {
        super.setRenderFrame(frame)
        if frame.width != fish2Pano.textureWidth || frame.height != fish2Pano.textureHeight {
            fish2Pano.updateTextureWidth(frame.width, height: frame.height)
        }
    }

    override func prepareRender() -> Bool {
        if super.prepareRender() {
            fish2Pano.prepareRender()
            return true
        }
        return false
    }
    */
}
