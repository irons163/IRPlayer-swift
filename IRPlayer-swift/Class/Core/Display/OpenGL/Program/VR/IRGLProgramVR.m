//
//  IRGLProgramVR.m
//  IRPlayer
//
//  Created by Phil on 2019/8/21.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramVR.h"
#import "IRGLVertexShaderGLSL.h"
#import "IRGLFragmentRGBShaderGLSL.h"
#import "IRGLFragmentYUVShaderGLSL.h"
#import "IRGLFragmentNV12ShaderGLSL.h"

@implementation IRGLProgramVR

- (NSString*)vertexShader {
    vertexShaderString = [IRGLVertexShaderGLSL getShardString];
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

-(BOOL)doScrollVerticalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    if(status & IRGLTransformControllerScrollToMaxY || status & IRGLTransformControllerScrollToMinY){
        return NO;
    }
    return YES;
}

//-(BOOL)loadShaders
//{
//    if([super loadShaders]){
//        [fish2Pano resolveUniforms:_program];
//        return YES;
//    }
//    return NO;
//}



//-(void)setRenderFrame:(IRFFVideoFrame*)frame{
//    [super setRenderFrame:frame];
//
//    if(frame.width != fish2Pano.textureWidth || frame.height != fish2Pano.textureHeight)
//        [fish2Pano updateTextureWidth:frame.width height:frame.height];
//}

//- (BOOL) prepareRender{
//    if([super prepareRender]){
//        [fish2Pano prepareRender];
//        return YES;
//    }
//    return NO;
//}

@end
