//
//  IRGLShaderParams.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLShaderParams.h"
#import <OpenGLES/ES3/gl.h>

@implementation IRGLShaderParams {
    GLint _uTextureMatrix;
}

- (void) resolveUniforms: (GLuint) program {
    _uTextureMatrix = glGetUniformLocation(program, "uTextureMatrix");
}

-(void)prepareRender {
    GLKMatrix4 texMatrix = GLKMatrix4MakeScale(1, -1, 1);
    //    texMatrix = GLKMatrix4Translate(texMatrix, 0, 0, -1);
    glUniformMatrix4fv(_uTextureMatrix, 1, GL_FALSE, texMatrix.m);
}

-(void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h {
    if(self.textureWidth != w || self.textureHeight != h){
    
    self.textureWidth = w;
    self.textureHeight = h;
    
    //    [self updateOutputWH];
    self.outputWidth = w;
    self.outputHeight = h;
    
    if(self.delegate)
        [self.delegate didUpdateOutputWH:w :h];
    }
}

@end
