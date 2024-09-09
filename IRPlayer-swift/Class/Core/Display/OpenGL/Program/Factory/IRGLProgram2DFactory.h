//
//  IRGLProgram2DFactory.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLSupportPixelFormat.h"
#import "IRMediaParameter.h"
@class IRGLProgram2D;

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProgram2DFactory : NSObject

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(nullable IRMediaParameter*)parameter;

@end

NS_ASSUME_NONNULL_END
