//
//  IRGLVertex3DShaderGLSL.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/11/3.
//

import Foundation
import GLKit

class IRGLVertex3DShaderGLSL: NSObject {

    static func getShardString() -> String {
        let vertex3DShaderString = """
        attribute highp vec4 position;
        attribute highp vec4 texcoord;
        uniform highp mat4 modelViewProjectionMatrix;
        varying highp vec2 v_texcoord;
        uniform highp mat4 uTextureMatrix;

        void main() {
            gl_Position = modelViewProjectionMatrix * position * vec4(1, -1, 1, 1);
            v_texcoord = (uTextureMatrix * texcoord).xy;
        }
        """
        return vertex3DShaderString
    }
}
