//
//  IRGLScope3D.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLScope2D.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLScope3D : IRGLScope2D

typedef NS_ENUM(NSInteger, TiltType){
    TILT_UNKNOWN = 0,
    TILT_UP,
    TILT_TOWARD,
    TILT_BACKWARD
};

@property TiltType tiltType;
@property float lat;
@property float lng;

-(instancetype)init:(IRGLScope3D*)old1;
-(instancetype)initBylat:(float)lat lng:(float) lng scale:(float)scale tiltType:(TiltType) tiltType panDegree:(float) panDegree w:(int)w h:(int)h;
@end

NS_ASSUME_NONNULL_END
