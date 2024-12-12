//
//  IRGLFragmentYUVShaderGLSL.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import GLKit

class IRGLFragmentYUVShaderGLSL {

    static func getShardString() -> String {
        let yuvFragmentShaderString = """
        varying highp vec2 v_texcoord;
        uniform sampler2D s_texture_y;
        uniform sampler2D s_texture_u;
        uniform sampler2D s_texture_v;
        uniform highp mat3 colorConversionMatrix;

        void main() {
            highp vec3 yuv;
            highp vec3 rgb;

            yuv.r = texture2D(s_texture_y, v_texcoord).r - (16.0 / 255.0);
            yuv.g = texture2D(s_texture_u, v_texcoord).r - 0.5;
            yuv.b = texture2D(s_texture_v, v_texcoord).r - 0.5;

            rgb = colorConversionMatrix * yuv;

            gl_FragColor = vec4(rgb, 1.0);
        }
        """

        return yuvFragmentShaderString
    }
}

