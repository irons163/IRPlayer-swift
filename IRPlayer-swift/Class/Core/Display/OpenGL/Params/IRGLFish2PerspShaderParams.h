//
//  IRGLFish2PerspShaderParams.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLShaderParams.h"
#import <OpenGLES/ES2/gl.h>
#import <GLKit/GLKMatrix4.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRGLFish2PerspShaderParams : IRGLShaderParams {
    
}

@property GLfloat preferredRotation;
@property (nonatomic) GLfloat fishaperture;
@property (nonatomic) GLint fishcenterx;
@property (nonatomic) GLint fishcentery;
@property (nonatomic) GLint fishradiush;
@property (nonatomic) GLint fishradiusv;
@property (nonatomic) GLint antialias;
@property (nonatomic) GLint enableTransformX;
@property (nonatomic) GLint enableTransformY;
@property (nonatomic) GLint enableTransformZ;
@property (nonatomic) GLfloat transformX;
@property (nonatomic) GLfloat transformY;
@property (nonatomic) GLfloat transformZ;
@property (nonatomic) GLfloat fishfov;
@property (nonatomic) GLfloat perspfov;

@end

NS_ASSUME_NONNULL_END
