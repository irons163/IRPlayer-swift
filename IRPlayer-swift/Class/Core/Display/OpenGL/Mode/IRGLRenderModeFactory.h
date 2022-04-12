//
//  IRGLRenderModeFactory.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLRenderMode.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLRenderModeFactory : NSObject

+ (NSArray<IRGLRenderMode*> *)createNormalModesWithParameter:(nullable IRMediaParameter *)parameter;
+ (NSArray<IRGLRenderMode*> *)createFisheyeModesWithParameter:(nullable IRMediaParameter *)parameter;
+ (IRGLRenderMode *)createVRModeWithParameter:(nullable IRMediaParameter *)parameter;
+ (IRGLRenderMode *)createDistortionModeWithParameter:(nullable IRMediaParameter *)parameter;
+ (IRGLRenderMode *)createFisheyeModeWithParameter:(nullable IRMediaParameter *)parameter;
+ (IRGLRenderMode *)createPanoramaModeWithParameter:(nullable IRMediaParameter *)parameter;

@end

NS_ASSUME_NONNULL_END
