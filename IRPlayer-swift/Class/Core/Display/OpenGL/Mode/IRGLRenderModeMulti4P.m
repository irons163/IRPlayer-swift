//
//  IRGLRenderModeMulti4P.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderModeMulti4P.h"
#import "IRGLProgram3DFisheye4PFactory.h"

@implementation IRGLRenderModeMulti4P

-(void)initProgramFactory{
    programFactory = [[IRGLProgram3DFisheye4PFactory alloc] init];
    self.shiftController.panAngle = 360;
    self.shiftController.tiltAngle = 360;
}

-(void)setContentMode:(IRGLRenderContentMode)contentMode{
    [super setContentMode:contentMode];
    self.program.contentMode = contentMode;
}

-(void)update{
//    [self setWideDegreeY:self.wideDegreeY];
//    self.shiftController.wideDegreeY = self.program.wideDegreeY;
}

@end
