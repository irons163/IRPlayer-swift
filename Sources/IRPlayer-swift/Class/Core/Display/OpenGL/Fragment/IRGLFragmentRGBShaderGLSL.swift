//
//  IRGLFragmentRGBShaderGLSL.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import GLKit

class IRGLFragmentRGBShaderGLSL {

    static func getShardString() -> String {
        let rgbFragmentShaderString = """
        varying highp vec2 v_texcoord;
        uniform sampler2D s_texture;

        void main() {
            gl_FragColor = texture2D(s_texture, v_texcoord);
        }
        """

        return rgbFragmentShaderString
    }
}
