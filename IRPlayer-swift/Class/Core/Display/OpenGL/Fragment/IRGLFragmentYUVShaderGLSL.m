//
//  IRGLFragmentYUVShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFragmentYUVShaderGLSL.h"
#import "IRGLDefine.h"

@implementation IRGLFragmentYUVShaderGLSL

+(NSString*) getShardString{
    NSString *yuvFragmentShaderString = SHADER_STRING
    (
     varying highp vec2 v_texcoord;
     uniform sampler2D s_texture_y;
     uniform sampler2D s_texture_u;
     uniform sampler2D s_texture_v;
     uniform highp mat3 colorConversionMatrix;
     
     void main()
     {
         //         highp float y = texture2D(s_texture_y, v_texcoord).r - (16.0/255.0);
         //         highp float u = texture2D(s_texture_u, v_texcoord).r - 0.5;
         //         highp float v = texture2D(s_texture_v, v_texcoord).r - 0.5;
         //
         //         highp float r = y +             1.402 * v;
         //         highp float g = y - 0.344 * u - 0.714 * v;
         //         highp float b = y + 1.772 * u;
         
         highp vec3 yuv;
         highp vec3 rgb;
         
         yuv.r = texture2D(s_texture_y, v_texcoord).r - (16.0/255.0);
         yuv.g = texture2D(s_texture_u, v_texcoord).r - 0.5;
         yuv.b = texture2D(s_texture_v, v_texcoord).r - 0.5;
         
         rgb = colorConversionMatrix * yuv;
         
         gl_FragColor = vec4(rgb,1.0);
     }
     );
    
    return yuvFragmentShaderString;
}

@end
