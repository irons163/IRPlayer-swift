//
//  IRGLFragmentNV12ShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFragmentNV12ShaderGLSL.h"
#import "IRGLDefine.h"

/////////////////////////////////////////////////
//// For VideoToolBox(NV12)
/////////////////////////////////////////////////

@implementation IRGLFragmentNV12ShaderGLSL

+(NSString*) getShardString{
    NSString *nv12ShaderString = SHADER_STRING
    (
     varying highp vec2 v_texcoord;
     precision mediump float;
     
     uniform float lumaThreshold;
     uniform float chromaThreshold;
     uniform sampler2D SamplerY;
     uniform sampler2D SamplerUV;
     uniform highp mat3 colorConversionMatrix;
     
     void main()
     {
         highp vec3 yuv;
         highp vec3 rgb;
         
         // Subtract constants to map the video range start at 0
         yuv.x = (texture2D(SamplerY, v_texcoord).r - (16.0/255.0))* lumaThreshold;
         yuv.yz = (texture2D(SamplerUV, v_texcoord).rg - vec2(0.5, 0.5))* chromaThreshold;
         
         rgb = colorConversionMatrix * yuv;
         
         gl_FragColor = vec4(rgb,1);
     }
     );
    
    return nv12ShaderString;
}

@end
