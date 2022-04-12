//
//  IRGLRenderBase.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderBase.h"
#import "IRMovieDecoder.h"

@implementation IRGLRenderBase

- (BOOL)isValid {
    return NO;
}

- (void)resolveUniforms:(GLuint)program {
    _uniformMatrix = glGetUniformLocation(program, "modelViewProjectionMatrix");
}

- (void)setVideoFrame:(IRFFVideoFrame *)frame {
    
}

- (BOOL)prepareRender:(GLuint)program {
    glUniformMatrix4fv(_uniformMatrix, 1, GL_FALSE, _modelviewProj.m);
    return YES;
}

- (void)setModelviewProj:(GLKMatrix4)modelviewProj {
    _modelviewProj = modelviewProj;
}

- (void)releaseRender {
    
}

@end
