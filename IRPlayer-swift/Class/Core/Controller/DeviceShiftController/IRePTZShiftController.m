//
//  IRePTZShiftController.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRePTZShiftController.h"
#import "IRGLProgram2D.h"

@implementation IRePTZShiftController{
    IRGLProgram2D* _program;
}

-(instancetype)init{
    if(self = [super init]){
        self.enabled = YES;
        self.panAngle = 0;
        self.tiltAngle = 0;
        self.panFactor = 1.0;
        self.tiltFactor = 1.0;
    }
    return self;
}

-(void)setProgram:(IRGLProgram2D*)program{
    _program = program;
//    self.wideDegreeX = _program.wideDegreeX;
//    self.wideDegreeY = _program.wideDegreeY;
//    self.wideDegreeX = 20;
//    self.wideDegreeY = 20;
//    _program.wideDegreeX = 360;
//    _program.wideDegreeY = 360;
}

-(void)shiftDegreeX:(float)degreeX degreeY:(float)degreeY{
    if(!self.enabled)
        return;
    
    if(self.panAngle == 0){
        degreeX = 0;
    }else{
        degreeX = degreeX * self.panFactor * 360 / self.panAngle;
    }
    
    if(self.tiltAngle == 0){
        degreeY = 0;
    }else{
        degreeY = degreeY * self.tiltFactor * 360 / self.tiltAngle;
    }
    
    [_program didPanByDegreeX:degreeX degreey:degreeY];
}

@end
