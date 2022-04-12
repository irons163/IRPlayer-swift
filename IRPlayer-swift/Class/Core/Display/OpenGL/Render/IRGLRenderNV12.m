//
//  IRGLRenderNV12.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderNV12.h"
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/glext.h>
#import "IRFFCVYUVVideoFrame.h"

@implementation IRGLRenderNV12 {
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;
    const GLfloat *_preferredConversion;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        
        // Set the default conversion to BT.709, which is the standard for HDTV.
        _preferredConversion = kIRColorConversion709;
        
        self.lumaThreshold = 1.0f;
        self.chromaThreshold = 1.0f;
        
//        if (!_videoTextureCache) {
//            CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [EAGLContext currentContext], NULL, &_videoTextureCache);
//            if (err != noErr) {
//                NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
//                return nil;
//            }
//        }
    }
    return self;
}

- (BOOL) isValid
{
    //    return (_textures[0] != 0);
    return (_lumaTexture != NULL);
}

- (void) resolveUniforms: (GLuint) program
{
    [super resolveUniforms:program];
    
    _uniformSamplers[UNIFORM_Y] = glGetUniformLocation(program, "SamplerY");
    _uniformSamplers[UNIFORM_UV] = glGetUniformLocation(program, "SamplerUV");
    
    _uniformParams[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(program, "colorConversionMatrix");
    _uniformParams[UNIFORM_LUMA_THRESHOLD] = glGetUniformLocation(program, "lumaThreshold");
    _uniformParams[UNIFORM_CHROMA_THRESHOLD] = glGetUniformLocation(program, "chromaThreshold");
}

- (void) setVideoFrame: (IRFFVideoFrame *) frame
{
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [EAGLContext currentContext], NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
    
    IRFFCVYUVVideoFrame *yuvFrame = (IRFFCVYUVVideoFrame *)frame;
    
    assert(yuvFrame.pixelBuffer != NULL);
    
    const NSUInteger frameWidth = frame.width;
    const NSUInteger frameHeight = frame.height;
    
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    
    [self cleanUpTextures];
    
    CFTypeRef colorAttachments = CVBufferGetAttachment(yuvFrame.pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
        _preferredConversion = kIRColorConversion601;
    }
    else {
        _preferredConversion = kIRColorConversion709;
    }
    
    CVReturn err;
    
    if([EAGLContext currentContext] && [EAGLContext currentContext].API == kEAGLRenderingAPIOpenGLES2){
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           yuvFrame.pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RED_EXT,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_RED_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_lumaTexture);
    }else{
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           yuvFrame.pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_LUMINANCE,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_LUMINANCE,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_lumaTexture);
    }
    
    if (!_lumaTexture || err) {
        NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
        return;
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // UV-plane.
    if([EAGLContext currentContext] && [EAGLContext currentContext].API == kEAGLRenderingAPIOpenGLES2){
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           yuvFrame.pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
    }else{
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           yuvFrame.pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG8,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
    }
    
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    
    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (BOOL) prepareRender: (GLuint) program
{
    [self resolveUniforms:program];
    
    [super prepareRender:program];
    
    if (!_lumaTexture || !_chromaTexture)
        return NO;
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glUniform1i(_uniformSamplers[UNIFORM_Y], 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
    glUniform1i(_uniformSamplers[UNIFORM_UV], 1);
    
    glUniformMatrix3fv(_uniformParams[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    glUniform1f(_uniformParams[UNIFORM_LUMA_THRESHOLD], self.lumaThreshold);
    glUniform1f(_uniformParams[UNIFORM_CHROMA_THRESHOLD], self.chromaThreshold);
    
    return YES;
}

- (void) dealloc
{
    [self releaseRender];
}

- (void)releaseRender {
    [self cleanUpTextures];
    
    if(_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
    _videoTextureCache = NULL;
}

- (void)cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
    
    // Periodic texture cache flush every frame
    if(_videoTextureCache)
        CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}
@end
