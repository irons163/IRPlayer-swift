//
//  IRGLProgramFactory.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProgram2D.h"
#import "IRGLProgram2DFisheye2Pano.h"
#import "IRGLProgram2DFisheye2Persp.h"
#import "IRGLProgram3DFisheye.h"
#import "IRGLProgramMulti4P.h"
#import "IRGLProgramVR.h"
#import "IRGLProgramDistortion.h"

NS_ASSUME_NONNULL_BEGIN

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
