//
//  IRGLFragmentRGBShaderGLSL.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFragmentRGBShaderGLSL.h"
#import "IRGLDefine.h"

@implementation IRGLFragmentRGBShaderGLSL

+(NSString*) getShardString{
    NSString *rgbFragmentShaderString = SHADER_STRING
    (
     varying highp vec2 v_texcoord;
     uniform sampler2D s_texture;
     
     void main()
     {
         gl_FragColor = texture2D(s_texture, v_texcoord);
     }
     );
    
    return rgbFragmentShaderString;
}

@end
