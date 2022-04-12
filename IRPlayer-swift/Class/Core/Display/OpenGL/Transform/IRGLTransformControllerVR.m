//
//  IRGLTransformControllerVR.m
//  IRPlayer
//
//  Created by Phil on 2019/8/22.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLTransformControllerVR.h"

@implementation IRGLTransformControllerVR

-(instancetype)initWithViewportWidth:(int)width viewportHeight:(int)height tileType:(TiltType)type{
    if(self = [super initWithViewportWidth:width
                            viewportHeight:height tileType:type]){
    }
    return self;
}

-(IRGLScopeRange*) getScopeRangeOf:(TiltType) type {
    switch(type){
        case TILT_UP: return [[IRGLScopeRange alloc] initWithMinLat:-190 maxLat:190 minLng:-180 maxLng:180 defaultLat:0 defaultLng:0];
        case TILT_TOWARD: return [[IRGLScopeRange alloc] initWithMinLat:-90 maxLat:90 minLng:-180 maxLng:180 defaultLat:0 defaultLng:0];
        case TILT_BACKWARD: return [[IRGLScopeRange alloc] initWithMinLat:-90 maxLat:90 minLng:-180 maxLng:180 defaultLat:0 defaultLng:0];
        default: ;
    }
    return nil;
}

- (void)scrollByDx:(float)dx dy:(float)dy {
    dy = -dy;
    [super scrollByDx:dx dy:dy];
}

- (void)setRc:(float)rc {
    self->rc = rc;
}

- (void)setFov:(float)fov {
    self->fov = fov;
}

- (float)rc {
    return self->rc;
}

- (float)fov {
    return self->fov;
}

@end
