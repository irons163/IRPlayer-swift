//
//  IRGLProjectionEquirectangular.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLProjection.h"
#import "IRGLDefine.h"
#import "IRGLMath.h"
#import <OpenGLES/ES2/gl.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRGLProjectionEquirectangular : NSObject<IRGLProjection>

-(instancetype)initWithTextureWidth:(float)w height:(float)h centerX:(float)centerX centerY:(float)centerY radius:(float)radius;
@end

NS_ASSUME_NONNULL_END
