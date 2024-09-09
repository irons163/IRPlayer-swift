//
//  IRGLProgram2DFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2DFactory.h"
#import <IRPlayer_swift/IRPlayer_swift-Swift.h>

@implementation IRGLProgram2DFactory

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(nullable IRMediaParameter*)parameter{
    return [IRGLProgramFactory createIRGLProgram2DWithPixelFormat:pixelFormat viewportRange:viewprotRange parameter:(IRMediaParameter*)parameter];
}

@end
