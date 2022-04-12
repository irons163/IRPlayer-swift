//
//  IRGLProgram2DFactory.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProgramFactory.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProgram2DFactory : NSObject

-(IRGLProgram2D*)createIRGLProgramWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;

@end

NS_ASSUME_NONNULL_END
