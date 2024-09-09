//
//  IRGLProgram3DFisheye4PFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram3DFisheye4PFactory.h"
#import <IRPlayer_swift/IRPlayer_swift-Swift.h>

@implementation IRGLProgram3DFisheye4PFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgram3DFisheye4PWithPixelFormat:pixelFormat viewportRange:viewprotRange parameter:(IRMediaParameter*)parameter];
}

@end
