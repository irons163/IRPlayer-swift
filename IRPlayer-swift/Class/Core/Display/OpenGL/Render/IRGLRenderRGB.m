//
//  IRGLRenderRGB.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderRGB.h"
#import "IRMovieDecoder.h"

#define TextureMagFilter GL_NEAREST//GL_LINEAR

@implementation IRGLRenderRGB

- (BOOL) isValid
{
    return (_texture != 0);
}

- (void) resolveUniforms: (GLuint) program
{
    [super resolveUniforms:program];
    
    _uniformSampler = glGetUniformLocation(program, "s_texture");
}

- (void) setVideoFrame: (IRFFVideoFrame *) frame
{
    IRVideoFrameRGB *rgbFrame = (IRVideoFrameRGB *)frame;
    
    assert(rgbFrame.rgb.length == rgbFrame.width * rgbFrame.height * 3);
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    if (0 == _texture)
        glGenTextures(1, &_texture);
    
    glBindTexture(GL_TEXTURE_2D, _texture);
    
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGB,
                 frame.width,
                 frame.height,
                 0,
                 GL_RGB,
                 GL_UNSIGNED_BYTE,
                 rgbFrame.rgb.bytes);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, TextureMagFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, TextureMagFilter);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (BOOL) prepareRender: (GLuint) program
{
    [super prepareRender:program];
    
    if (_texture == 0)
        return NO;
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glUniform1i(_uniformSampler, 0);
    
    return YES;
}

- (void) dealloc
{
    [self releaseRender];
}

- (void)releaseRender {
    if (_texture) {
        glDeleteTextures(1, &_texture);
        _texture = 0;
    }
}

@end
