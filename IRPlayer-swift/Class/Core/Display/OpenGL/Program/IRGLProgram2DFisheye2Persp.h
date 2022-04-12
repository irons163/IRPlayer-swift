//
//  IRGLProgram2DFisheye2Persp.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProgram2D.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProgram2DFisheye2Persp  : IRGLProgram2D

- (void)setTransformX:(float)x Y:(float)y;
@end

NS_ASSUME_NONNULL_END
