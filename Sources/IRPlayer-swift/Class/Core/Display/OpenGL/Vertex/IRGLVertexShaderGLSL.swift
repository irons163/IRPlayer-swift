//
//  IRGLVertexShaderGLSL.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/3.
//

import Foundation
import GLKit

class IRGLVertexShaderGLSL: NSObject {

    static func getShardString() -> String {
        let vertexShaderString = """
        attribute highp vec4 position;
        attribute highp vec4 texcoord;
        uniform highp mat4 modelViewProjectionMatrix;
        varying highp vec2 v_texcoord;
        uniform highp mat4 uTextureMatrix;

        void main() {
            gl_Position = modelViewProjectionMatrix * position;
            v_texcoord = texcoord.xy;
        }
        """
        return vertexShaderString
    }
}
