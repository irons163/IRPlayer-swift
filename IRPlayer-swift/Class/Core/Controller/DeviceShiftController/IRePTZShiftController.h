//
//  IRePTZShiftController.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
@class IRGLProgram2D;

NS_ASSUME_NONNULL_BEGIN

@interface IRePTZShiftController : NSObject

@property BOOL enabled;
@property (nonatomic) float panAngle;
@property (nonatomic) float tiltAngle;
@property (nonatomic) float panFactor;
@property (nonatomic) float tiltFactor;

- (void)setProgram:(IRGLProgram2D*)program;
- (void)shiftDegreeX:(float)degreeX degreeY:(float)degreeY;
@end

NS_ASSUME_NONNULL_END
