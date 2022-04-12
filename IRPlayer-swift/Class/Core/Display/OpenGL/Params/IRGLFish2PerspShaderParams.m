//
//  IRGLFish2PerspShaderParams.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLFish2PerspShaderParams.h"
#import "IRGLMath.h"

@implementation IRGLFish2PerspShaderParams {
    enum
    {
        UNIFORM_ROTATION_ANGLE,
        UNIFORM_TEXTURE_WIDTH,
        UNIFORM_TEXTURE_HEIGHT,
        UNIFORM_FISH_APERTURE,
        UNIFORM_FISH_CENTERX,
        UNIFORM_FISH_CENTERY,
        UNIFORM_FISH_RADIUS_H,
        UNIFORM_FISH_RADIUS_V,
        UNIFORM_OUTPUT_WIDTH,
        UNIFORM_OUTPUT_HEIGHT,
        UNIFORM_ANTIALIAS,
        UNIFORM_FISHFOV,
        UNIFORM_PERSPFOV,
        UNIFORM_ENABLE_TRANSFORM_X,
        UNIFORM_ENABLE_TRANSFORM_Y,
        UNIFORM_ENABLE_TRANSFORM_Z,
        UNIFORM_TRANSFORM_X,
        UNIFORM_TRANSFORM_Y,
        UNIFORM_TRANSFORM_Z,
        NUM_UNIFORMS
    };
    
    GLint _uniformSamplers[NUM_UNIFORMS];
    GLint _uTextureMatrix;
}

-(instancetype)init {
    if(self = [super init]){
        [self setDefaultValues];
    }
    return self;
}

- (void)resolveUniforms:(GLuint)program {
    _uTextureMatrix = glGetUniformLocation(program, "uTextureMatrix");
    
    _uniformSamplers[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(program, "preferredRotation");
    _uniformSamplers[UNIFORM_TEXTURE_WIDTH] = glGetUniformLocation(program, "fishwidth");
    _uniformSamplers[UNIFORM_TEXTURE_HEIGHT] = glGetUniformLocation(program, "fishheight");
    _uniformSamplers[UNIFORM_FISH_APERTURE] = glGetUniformLocation(program, "fishaperture");
    _uniformSamplers[UNIFORM_FISH_CENTERX] = glGetUniformLocation(program, "fishcenterx");
    _uniformSamplers[UNIFORM_FISH_CENTERY] = glGetUniformLocation(program, "fishcentery");
    _uniformSamplers[UNIFORM_FISH_RADIUS_H] = glGetUniformLocation(program, "fishradiush");
    _uniformSamplers[UNIFORM_FISH_RADIUS_V] = glGetUniformLocation(program, "fishradiusv");
    _uniformSamplers[UNIFORM_OUTPUT_WIDTH] = glGetUniformLocation(program, "perspectivewidth");
    _uniformSamplers[UNIFORM_OUTPUT_HEIGHT] = glGetUniformLocation(program, "perspectiveheight");
    _uniformSamplers[UNIFORM_ANTIALIAS] = glGetUniformLocation(program, "antialias");
    _uniformSamplers[UNIFORM_FISHFOV] = glGetUniformLocation(program, "fishfov");
    _uniformSamplers[UNIFORM_PERSPFOV] = glGetUniformLocation(program, "perspfov");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_X] = glGetUniformLocation(program, "enableTransformX");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Y] = glGetUniformLocation(program, "enableTransformY");
    _uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Z] = glGetUniformLocation(program, "enableTransformZ");
    _uniformSamplers[UNIFORM_TRANSFORM_X] = glGetUniformLocation(program, "transformX");
    _uniformSamplers[UNIFORM_TRANSFORM_Y] = glGetUniformLocation(program, "transformY");
    _uniformSamplers[UNIFORM_TRANSFORM_Z] = glGetUniformLocation(program, "transformZ");
}

-(void)prepareRender {
    // 0 and 1 are the texture IDs of _lumaTexture and _chromaTexture respectively.
    glUniform1f(_uniformSamplers[UNIFORM_ROTATION_ANGLE], self.preferredRotation);
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_WIDTH], self.textureWidth);
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_HEIGHT], self.textureHeight);
    glUniform1f(_uniformSamplers[UNIFORM_FISH_APERTURE], self.fishaperture);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_CENTERX], self.fishcenterx);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_CENTERY], self.fishcentery);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_RADIUS_H], self.fishradiush);
    glUniform1i(_uniformSamplers[UNIFORM_FISH_RADIUS_V], self.fishradiusv);
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_WIDTH], self.outputWidth);
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_HEIGHT], self.outputHeight);
    glUniform1i(_uniformSamplers[UNIFORM_ANTIALIAS], self.antialias);
    glUniform1f(_uniformSamplers[UNIFORM_FISHFOV], self.fishfov);
    glUniform1f(_uniformSamplers[UNIFORM_PERSPFOV], self.perspfov);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_X], self.enableTransformX);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Y], self.enableTransformY);
    glUniform1i(_uniformSamplers[UNIFORM_ENABLE_TRANSFORM_Z], self.enableTransformZ);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_X], self.transformX);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_Y], self.transformY);
    glUniform1f(_uniformSamplers[UNIFORM_TRANSFORM_Z], self.transformZ);
    
    //        GLKMatrix4 texMatrix = GLKMatrix4Translate(GLKMatrix4Identity, 0, 0, 1);
    //        GLKMatrix4 texMatrix = GLKMatrix4Identity;
    GLKMatrix4 texMatrix = GLKMatrix4MakeScale(1, -1, 1);
    //    texMatrix = GLKMatrix4Translate(texMatrix, 0, 0, -1);
    glUniformMatrix4fv(_uTextureMatrix, 1, GL_FALSE, texMatrix.m);
}

-(void)setDefaultValues
{
    [super setTextureWidth:-1];       // Derived from input fisheye file
    [super setTextureHeight:-1];
    _fishaperture = 180.0;   // Aperture of the fisheye
    _fishcenterx = -1;     // Center of the fisheye (pixels), measured from lower-left corner
    _fishcentery = -1;
    _fishradiush = -1;     // Radius of the fisheye (pixels)
    _fishradiusv = -1;
    [super setOutputWidth:1024];     // Width and height of panoramic view
    [super setOutputHeight:-1];      // If not specified, work it out
    _antialias = 2;
    _fishfov = 180.0 * DTOR;
    _perspfov = 100.0 * DTOR;
}

-(void)setOutputWidth:(GLint)outputWidth {
    if(self.outputWidth == outputWidth)
        return;
    [super setOutputWidth:outputWidth];
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_WIDTH], self.outputWidth);
}

-(void)setOutputHeight:(GLint)outputHeight {
    if(self.outputHeight == outputHeight)
        return;
    [super setOutputHeight:outputHeight];
    glUniform1i(_uniformSamplers[UNIFORM_OUTPUT_HEIGHT], self.outputHeight);
}

-(void)setTextureWidth:(GLint)textureWidth {
    if(self.textureWidth == textureWidth)
        return;
    [super setTextureWidth:textureWidth];
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_WIDTH], self.textureWidth);
}

-(void)setTextureHeight:(GLint)textureHeight {
    if(self.textureHeight == textureHeight)
        return;
    [super setTextureHeight:textureHeight];
    glUniform1i(_uniformSamplers[UNIFORM_TEXTURE_HEIGHT], self.textureHeight);
    
}

-(void)setFishfov:(GLfloat)fishfov {
    if(self.fishfov == fishfov)
        return;
    _fishfov = fishfov;
    glUniform1i(_uniformSamplers[UNIFORM_FISHFOV], self.fishfov);
}

-(void)setPerspfov:(GLfloat)perspfov {
    if(self.perspfov == perspfov)
        return;
    _perspfov = perspfov;
    glUniform1i(_uniformSamplers[UNIFORM_PERSPFOV], self.perspfov);
}

-(void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h {
    //    if(self.textureWidth != w || self.textureHeight != h){
    self.textureWidth = w;
    self.textureHeight = h;
    
    [self updateOutputWH];
    
    if(self.delegate)
        [self.delegate didUpdateOutputWH:self.outputWidth :self.outputHeight];
    //    }
}

-(void)updateOutputWH {
    //    self.outputWidth = 2048;
    //    self.outputHeight = (int)(self.outputWidth * tan(0.5*vapertureRadians) / (0.5*(long2Radians - long1Radians)));
    self.outputWidth = 1280;
    self.outputHeight = 720;
    
    //    self.fishcenterx = 708;
    self.fishcenterx = 680;
    //    self.fishcentery = 550;
    self.fishcentery = 545;
    //    self.fishradiush = 516;
    self.fishradiush = 515;
    self.enableTransformX = 1;
    //    self.transformX = -45;
    self.enableTransformY = 1;
    //    self.transformY = -90;
    self.enableTransformZ = 1;
    //    self.transformZ = 60;
    float fishfovDegree = 180;
    
    if(fishfovDegree > 360.0)
        fishfovDegree = 360.0;
    
    self.fishfov = fishfovDegree * DTOR;
    
    float perspfovDegree = 100;
    if (perspfovDegree > 170.0)
        perspfovDegree = 170.0;
    
    self.perspfov = perspfovDegree * DTOR;
}

//-(void)setModelviewProj:(GLKMatrix4) modelviewProj{
//    _modelviewProj = modelviewProj;
//}

@end
