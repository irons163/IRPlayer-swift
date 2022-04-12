//
//  IRGLFragmentFish2PanoShaderGLSL.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLSupportPixelFormat.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLFragmentFish2PanoShaderGLSL : NSObject

+(NSString*) getShardString:(IRPixelFormat)pixelFormat antialias:(int)antialias;
@end

NS_ASSUME_NONNULL_END
