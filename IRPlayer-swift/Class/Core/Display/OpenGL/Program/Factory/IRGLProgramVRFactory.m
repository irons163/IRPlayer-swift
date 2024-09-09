//
//  IRGLProgramVRFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/8/21.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramVRFactory.h"
#import <IRPlayer_swift/IRPlayer_swift-Swift.h>

@implementation IRGLProgramVRFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgramVRWithPixelFormat:pixelFormat viewportRange:viewprotRange parameter:(IRMediaParameter*)parameter];
}

@end
