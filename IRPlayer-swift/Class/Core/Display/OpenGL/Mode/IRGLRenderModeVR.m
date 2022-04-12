//
//  IRGLRenderModeVR.m
//  IRPlayer
//
//  Created by Phil on 2019/8/21.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderModeVR.h"
#import "IRGLProgramVRFactory.h"

@implementation IRGLRenderModeVR

-(void)initProgramFactory{
    programFactory = [[IRGLProgramVRFactory alloc] init];
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
