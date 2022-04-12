//
//  IRGLTransformControllerDistortion.h
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLTransformControllerVR.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLTransformControllerDistortion : IRGLTransformControllerVR

-(GLKMatrix4)getModelViewProjectionMatrix2;
@end

NS_ASSUME_NONNULL_END
