//
//  IRGLFish2PanoShaderParams.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLShaderParams.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLFish2PanoShaderParams : IRGLShaderParams {
    
}

@property GLfloat preferredRotation;
@property (nonatomic) GLfloat fishaperture;
@property (nonatomic) GLint fishcenterx;
@property (nonatomic) GLint fishcentery;
@property (nonatomic) GLint fishradiush;
@property (nonatomic) GLint fishradiusv;
@property (nonatomic) GLint antialias;
@property (nonatomic) GLfloat vaperture;
@property (nonatomic) GLfloat lat1;
@property (nonatomic) GLfloat lat2;
@property (nonatomic) GLfloat long1;
@property (nonatomic) GLfloat long2;
@property (nonatomic) GLint enableTransformX;
@property (nonatomic) GLint enableTransformY;
@property (nonatomic) GLint enableTransformZ;
@property (nonatomic) GLfloat transformX;
@property (nonatomic) GLfloat transformY;
@property (nonatomic) GLfloat transformZ;
@property (nonatomic) GLfloat offsetX;
//@property int viewportWidth;
//@property int viewportHeight;
//@property (weak) id<Shader> delegate;

@end

NS_ASSUME_NONNULL_END
