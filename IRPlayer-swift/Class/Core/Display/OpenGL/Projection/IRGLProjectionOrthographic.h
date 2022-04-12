//
//  IRGLProjectionOrthographic.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProjection.h"
#import <OpenGLES/ES2/gl.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProjectionOrthographic : NSObject<IRGLProjection>

-(instancetype)initWithTextureWidth:(float)w hidth:(float)h;
@end

NS_ASSUME_NONNULL_END
