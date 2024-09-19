//
//  IRGLFragmentNV12ShaderGLSL.swift
//  IRPlayer-swift
//
//  Created by irons on 2024/9/19.
//

import Foundation
import GLKit

class IRGLFragmentNV12ShaderGLSL {

    static func getShardString() -> String {
        let nv12ShaderString = """
        varying highp vec2 v_texcoord;
        precision mediump float;

        uniform float lumaThreshold;
        uniform float chromaThreshold;
        uniform sampler2D SamplerY;
        uniform sampler2D SamplerUV;
        uniform highp mat3 colorConversionMatrix;

        void main() {
            highp vec3 yuv;
            highp vec3 rgb;

            // Subtract constants to map the video range start at 0
            yuv.x = (texture2D(SamplerY, v_texcoord).r - (16.0 / 255.0)) * lumaThreshold;
            yuv.yz = (texture2D(SamplerUV, v_texcoord).rg - vec2(0.5, 0.5)) * chromaThreshold;

            rgb = colorConversionMatrix * yuv;

            gl_FragColor = vec4(rgb, 1.0);
        }
        """

        return nv12ShaderString
    }
}
