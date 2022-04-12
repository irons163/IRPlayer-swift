//
//  IRGLRenderYUV.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderYUV.h"
#import "IRFFAVYUVVideoFrame.h"

#define TextureMagFilter GL_NEAREST//GL_LINEAR

enum
{
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_PARAMS
};

@implementation IRGLRenderYUV {
    GLint _uniformParams[NUM_PARAMS];
    const GLfloat *_preferredConversion;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        
        // Set the default conversion to BT.709, which is the standard for HDTV.
        _preferredConversion = kIRColorConversion709;
    }
    return self;
}

- (BOOL) isValid
{
    return (_textures[0] != 0);
}

- (void) resolveUniforms: (GLuint) program
{
    [super resolveUniforms:program];
    
    _uniformSamplers[0] = glGetUniformLocation(program, "s_texture_y");
    _uniformSamplers[1] = glGetUniformLocation(program, "s_texture_u");
    _uniformSamplers[2] = glGetUniformLocation(program, "s_texture_v");
    
    _uniformParams[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(program, "colorConversionMatrix");
}

- (void) setVideoFrame: (IRFFVideoFrame *) frame
{
    IRFFAVYUVVideoFrame *yuvFrame = (IRFFAVYUVVideoFrame *)frame;
    
//    assert(yuvFrame.luma.length == yuvFrame.width * yuvFrame.height);
//    assert(yuvFrame.chromaB.length == (yuvFrame.width * yuvFrame.height) / 4);
//    assert(yuvFrame.chromaR.length == (yuvFrame.width * yuvFrame.height) / 4);
    
    const NSUInteger frameWidth = frame.width;
    const NSUInteger frameHeight = frame.height;
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    BOOL isFirst = false;
    if (0 == _textures[0])
        isFirst = true;
    
    if (0 == _textures[0])
        glGenTextures(3, _textures);
    
//    const UInt8 *pixels[3] = { yuvFrame.luma.bytes, yuvFrame.chromaB.bytes, yuvFrame.chromaR.bytes };
    const UInt8 *pixels[3] = { yuvFrame.luma, yuvFrame.chromaB, yuvFrame.chromaR };
    const NSUInteger widths[3]  = { frameWidth, frameWidth / 2, frameWidth / 2 };
    const NSUInteger heights[3] = { frameHeight, frameHeight / 2, frameHeight / 2 };
    
    for (int i = 0; i < 3; ++i) {
        
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        
        if (isFirst){
            glTexImage2D(GL_TEXTURE_2D,
                         0,
                         GL_LUMINANCE,
                         widths[i],
                         heights[i],
                         0,
                         GL_LUMINANCE,
                         GL_UNSIGNED_BYTE,
                         pixels[i]);
            
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, TextureMagFilter);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, TextureMagFilter);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }else{
            glTexSubImage2D(GL_TEXTURE_2D,
                            0,
                            0,
                            0,
                            widths[i],
                            heights[i],
                            GL_LUMINANCE,
                            GL_UNSIGNED_BYTE,
                            pixels[i]);
        }
    }
}

- (BOOL) prepareRender: (GLuint) program
{
    [super prepareRender:program];
    
    if (_textures[0] == 0)
        return NO;
    
    for (int i = 0; i < 3; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glUniform1i(_uniformSamplers[i], i);
    }
    
    glUniformMatrix3fv(_uniformParams[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    return YES;
}

- (void) dealloc
{
    [self releaseRender];
}

- (void)releaseRender {
    if (_textures[0]){
        glDeleteTextures(3, _textures);
        _textures[0] = 0;
    }
}

@end
