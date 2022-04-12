//
//  IRGLRenderNV12.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLRenderBase.h"

NS_ASSUME_NONNULL_BEGIN
/////////////////////////////////////////////////
//// For VideoToolBox(NV12)
/////////////////////////////////////////////////

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    NUM_SAMPLERS
};

enum
{
    UNIFORM_COLOR_CONVERSION_MATRIX,
    UNIFORM_LUMA_THRESHOLD,
    UNIFORM_CHROMA_THRESHOLD,
    NUM_PARAMS
};

@interface IRGLRenderNV12 : IRGLRenderBase {
    
    GLint _uniformSamplers[NUM_SAMPLERS];
    GLint _uniformParams[NUM_PARAMS];
    GLuint _textures[2];
    //    CVOpenGLESTextureRef _lumaTexture;
}

@property GLfloat chromaThreshold;
@property GLfloat lumaThreshold;

//-(void)updateOutputWH;
@end

NS_ASSUME_NONNULL_END
