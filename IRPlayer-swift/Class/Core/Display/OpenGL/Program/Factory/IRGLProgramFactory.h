//
//  IRGLProgramFactory.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLSupportPixelFormat.h"
#import "IRMediaParameter.h"

NS_ASSUME_NONNULL_BEGIN

@class IRGLProgram2D;
@class IRGLProgram2DFisheye2Pano;
@class IRGLProgram2DFisheye2Persp;
@class IRGLProgram3DFisheye;
@class IRGLProgramMulti4P;
@class IRGLProgramVR;
@class IRGLProgramDistortion;

@interface IRGLProgramFactory : NSObject

+(IRGLProgram2D*) createIRGLProgram2DWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgram2DFisheye2Pano*) createIRGLProgram2DFisheye2PanoWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgram2DFisheye2Persp*) createIRGLProgram2DFisheye2PerspWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgram3DFisheye*) createIRGLProgram3DFisheyeWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgramMulti4P*) createIRGLProgram2DFisheye2Persp4PWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgramMulti4P*) createIRGLProgram3DFisheye4PWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgramVR*) createIRGLProgramVRWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
+(IRGLProgramDistortion*) createIRGLProgramDistortionWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
@end

NS_ASSUME_NONNULL_END
