//
//  IRGLTransformControllerVR.h
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLTransformController3DFisheye.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLTransformControllerVR : IRGLTransformController3DFisheye

@property (nonatomic) float rc;
@property (nonatomic) float fov;

@end

NS_ASSUME_NONNULL_END
