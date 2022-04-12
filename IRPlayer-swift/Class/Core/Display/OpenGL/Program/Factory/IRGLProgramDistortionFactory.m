//
//  IRGLProgramDistortionFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/8/23.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramDistortionFactory.h"

@implementation IRGLProgramDistortionFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgramDistortionWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
}

@end
