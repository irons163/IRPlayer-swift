//
//  IRGLRenderRGB.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLRenderBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLRenderRGB : IRGLRenderBase {
    
    GLint _uniformSampler;
    GLuint _texture;
}
@end

NS_ASSUME_NONNULL_END
