//
//  IRGLProgram2DFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2DFactory.h"

@implementation IRGLProgram2DFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgram2DWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
}

@end
