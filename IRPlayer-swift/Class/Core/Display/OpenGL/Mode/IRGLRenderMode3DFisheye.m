//
//  IRGLRenderMode3DFisheye.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderMode3DFisheye.h"
#import "IRGLProgram3DFisheyeFactory.h"

@implementation IRGLRenderMode3DFisheye

-(void)initProgramFactory{
    programFactory = [[IRGLProgram3DFisheyeFactory alloc] init];
    self.shiftController.panAngle = 180;
    self.shiftController.tiltAngle = 360;
}

-(void)setContentMode:(IRGLRenderContentMode)contentMode{
    [super setContentMode:contentMode];
    self.program.contentMode = contentMode;
}

@end
