//
//  IRGLVertex3DShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLVertex3DShaderGLSL.h"

@implementation IRGLVertex3DShaderGLSL

+(NSString*) getShardString{
    NSString *vertex3DShaderString = SHADER_STRING
    (
     attribute highp vec4 position;
     attribute highp vec4 texcoord;
     uniform highp mat4 modelViewProjectionMatrix;
     varying highp vec2 v_texcoord;
     uniform highp mat4 uTextureMatrix;
     
     void main()
     {
         gl_Position = modelViewProjectionMatrix * position * vec4(1, -1, 1, 1);
         v_texcoord = (uTextureMatrix * texcoord).xy;
     }
     );
    
    return vertex3DShaderString;
}
@end
