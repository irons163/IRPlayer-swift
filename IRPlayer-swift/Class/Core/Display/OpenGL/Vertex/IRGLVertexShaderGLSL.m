//
//  IRGLVertexShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLVertexShaderGLSL.h"

@implementation IRGLVertexShaderGLSL

+(NSString*) getShardString{
    NSString *vertexShaderString = SHADER_STRING
    (
     attribute highp vec4 position;
     attribute highp vec4 texcoord;
     uniform highp mat4 modelViewProjectionMatrix;
     varying highp vec2 v_texcoord;
     uniform highp mat4 uTextureMatrix;
     
     void main()
     {
         gl_Position = modelViewProjectionMatrix * position;
         v_texcoord = texcoord.xy;
     }
     );
    
    return vertexShaderString;
}

@end
