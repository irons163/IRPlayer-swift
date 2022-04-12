//
//  IRGLRenderBase.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import "IRGLRender.h"

NS_ASSUME_NONNULL_BEGIN
// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kIRColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kIRColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

@interface IRGLRenderBase : NSObject<IRGLRender> {
    GLKMatrix4 _modelviewProj;
    GLint  _uniformMatrix;
}
@end

NS_ASSUME_NONNULL_END
