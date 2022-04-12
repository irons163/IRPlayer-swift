//
//  IRGLRenderMode2DFIsheye2Pano.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLRenderMode2DFisheye2Pano.h"
#import "IRGLProgram2DFisheye2PanoFactory.h"

@implementation IRGLRenderMode2DFisheye2Pano

-(void)initProgramFactory{
    programFactory = [[IRGLProgram2DFisheye2PanoFactory alloc] init];
    self.shiftController.panAngle = 180;
    self.shiftController.tiltAngle = 360;
}

-(void)setContentMode:(IRGLRenderContentMode)contentMode{
    [super setContentMode:contentMode];
    self.program.contentMode = contentMode;
}

@end
