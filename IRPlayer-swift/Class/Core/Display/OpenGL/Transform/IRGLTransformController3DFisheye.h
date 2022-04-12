//
//  IRGLTransformController3DFisheye.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLTransformController.h"
#import "IRGLScope3D.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLTransformController3DFisheye : IRGLTransformController {
    float camera[3];
    float rc;
    float fov, tanbase;
    GLKMatrix4 projectMatrix, modelMatrix;
}

@property GLKMatrix4 viewMatrix;

-(instancetype)initWithViewportWidth:(int)width viewportHeight:(int)height tileType:(TiltType)type;
-(IRGLScopeRange*) getScopeRange;
@end
NS_ASSUME_NONNULL_END
