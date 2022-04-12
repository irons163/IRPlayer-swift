//
//  IRGLProgram2DFisheye2PanoFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2DFisheye2PanoFactory.h"

@implementation IRGLProgram2DFisheye2PanoFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgram2DFisheye2PanoWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
}

@end
