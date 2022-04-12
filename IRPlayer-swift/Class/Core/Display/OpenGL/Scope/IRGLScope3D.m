//
//  IRGLScope3D.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLScope3D.h"

@implementation IRGLScope3D

-(instancetype)init{
    if(self = [super init]){
        self.tiltType = TILT_UP;
        self.lat = self.lng = 0.0f;
    }
    return self;
}

-(instancetype)init:(IRGLScope3D*)old1{
    if(self = [super init:old1]){
        self.tiltType = old1.tiltType;
        self.lat = old1.lat;
        self.lng = old1.lng;
    }
    return self;
}

-(instancetype)initBylat:(float)lat lng:(float) lng scale:(float)scale tiltType:(TiltType) tiltType panDegree:(float) panDegree w:(int)w h:(int)h{
    if(self = [super initBysx:scale sy:scale offx:0 offy:0 degree:panDegree w:w h:h]){
        self.tiltType = tiltType;
        self.lat = lat;
        self.lng = lng;
    }
    return self;
}

@end
