//
//  IRGLProgram3DFisheye.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram3DFisheye.h"
#import "IRGLVertex3DShaderGLSL.h"
#import "IRGLFragmentRGBShaderGLSL.h"
#import "IRGLFragmentYUVShaderGLSL.h"
#import "IRGLFragmentNV12ShaderGLSL.h"

@implementation IRGLProgram3DFisheye

- (NSString*)vertexShader {
    vertexShaderString = [IRGLVertex3DShaderGLSL getShardString];
    return vertexShaderString;
}

- (NSString*)fragmentShader {
    switch (_pixelFormat) {
        case RGB_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentRGBShaderGLSL getShardString];
            break;
        case YUV_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentYUVShaderGLSL getShardString];
            break;
        case NV12_IRPixelFormat:
            fragmentShaderString = [IRGLFragmentNV12ShaderGLSL getShardString];
            break;
    }
    return fragmentShaderString;
}

- (void)didUpdateOutputWH:(int)w :(int)h {
    if(!self.parameter.autoUpdate || (w == self.parameter.width && h == self.parameter.height))
        return;
    
    self.parameter.width = w;
    self.parameter.height = h;
    [self.mapProjection updateWithParameter:self.parameter];
}

- (BOOL)doScrollVerticalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController {
    if(status & IRGLTransformControllerScrollToMaxY || status & IRGLTransformControllerScrollToMinY){
        return NO;
    }
    return YES;
}

@end
