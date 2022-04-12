//
//  IRGLProgram3DFisheyeFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram3DFisheyeFactory.h"

@implementation IRGLProgram3DFisheyeFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgram3DFisheyeWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
}

@end
