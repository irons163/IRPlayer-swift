//
//  IRGLRender.h
//  IRPlayer
//
//  Created by irons on 2020/2/10.
//  Copyright © 2020 Phil. All rights reserved.
//

#import <GLKit/GLKMatrix4.h>
#import "IRFFVideoFrame.h"

@protocol IRGLRender
- (BOOL)isValid;
- (void)resolveUniforms:(GLuint)program;
- (void)setVideoFrame:(IRFFVideoFrame *)frame;
- (void)setModelviewProj:(GLKMatrix4)modelviewProj;
- (BOOL)prepareRender:(GLuint)program;
- (void)releaseRender;
@end
