//
//  IRGLRenderModeDistortion.m
//  IRPlayer
//
//  Created by Phil on 2019/8/23.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderModeDistortion.h"
#import "IRGLProgramDistortionFactory.h"

@implementation IRGLRenderModeDistortion

-(void)initProgramFactory{
    programFactory = [[IRGLProgramDistortionFactory alloc] init];
    self.shiftController.panAngle = 360;
    self.shiftController.tiltAngle = 180;
}

-(void)setDefaultScale:(float)scale{
    [super setDefaultScale:scale];
    //    [self.program setDefaultScale:scale];
}

-(void)setContentMode:(IRGLRenderContentMode)contentMode{
    [super setContentMode:contentMode];
    self.program.contentMode = contentMode;
}

@end
