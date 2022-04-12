//
//  IRGLProgram2DFisheye2Pano.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2DFisheye2Pano.h"
#import "IRGLFish2PanoShaderParams.h"
#import "IRGLVertexShaderGLSL.h"
#import "IRGLFragmentFish2PanoShaderGLSL.h"
#import "IRFisheyeParameter.h"

@interface IRGLProgram2DFisheye2Pano(Protected)
-(void)initShaderParams;
@end

@implementation IRGLProgram2DFisheye2Pano{
    IRGLFish2PanoShaderParams *fish2Pano;
    float willScrollX, willScrollY;
}

-(NSString*)vertexShader{
    vertexShaderString = [IRGLVertexShaderGLSL getShardString];
    return vertexShaderString;
}

-(NSString*)fragmentShader{
    fragmentShaderString = [IRGLFragmentFish2PanoShaderGLSL getShardString:_pixelFormat antialias:fish2Pano.antialias];
    return fragmentShaderString;
}

- (void)setupWithParameter:(IRMediaParameter *)parameter {
    if (!parameter) return;
    
    if ([parameter isKindOfClass:[IRMediaParameter class]]) {
        fish2Pano.fishcenterx = parameter.width / 2;
        fish2Pano.fishcentery = parameter.height / 2;
        fish2Pano.fishradiush = parameter.width / 2;
        fish2Pano.fishradiusv = parameter.height / 2;
    } else if ([parameter isKindOfClass:[IRFisheyeParameter class]]) {
        IRFisheyeParameter *fishParameter = (IRFisheyeParameter *)parameter;
        fish2Pano.fishcenterx = fishParameter.cx;
        fish2Pano.fishcentery = fishParameter.cy;
        fish2Pano.fishradiush = fishParameter.rx;
        fish2Pano.fishradiusv = fishParameter.ry;
    }
}

- (void)initShaderParams {
    fish2Pano = [[IRGLFish2PanoShaderParams alloc] init];
    fish2Pano.delegate = self;
}

- (void)setContentMode:(IRGLRenderContentMode)contentMode {
    [super setContentMode:contentMode];
    if(self.contentMode != contentMode){
        [self updateTextureWidth:fish2Pano.textureWidth height:fish2Pano.textureHeight];
    }
}

- (void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h {
    [super updateTextureWidth:w height:h];
    [fish2Pano updateTextureWidth:w height:h];
}

- (BOOL)loadShaders {
    if([super loadShaders]){
        [fish2Pano resolveUniforms:_program];
        return YES;
    }
    return NO;
}

- (void)setRenderFrame:(IRFFVideoFrame*)frame {
    [super setRenderFrame:frame];
    
    if(frame.width != fish2Pano.textureWidth || frame.height != fish2Pano.textureHeight)
        [fish2Pano updateTextureWidth:frame.width height:frame.height];
}

- (BOOL)prepareRender {
    if([super prepareRender]){
        [fish2Pano prepareRender];
        return YES;
    }
    return NO;
}

- (void)willScrollByDx:(float)dx dy:(float)dy withTramsformController:(IRGLTransformController *)tramsformController {
    willScrollX = dx;
    willScrollY = dy;
}

- (BOOL)doScrollHorizontalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController {
    if(status & IRGLTransformControllerScrollToMaxX || status & IRGLTransformControllerScrollToMinX){
        fish2Pano.offsetX -= (willScrollX / [self.tramsformController getScope].scaleX * (fish2Pano.outputWidth / (float)[self.tramsformController getScope].W));
        while (fish2Pano.offsetX > fish2Pano.outputWidth || fish2Pano.offsetX < -fish2Pano.outputWidth) {
            if(fish2Pano.offsetX > fish2Pano.outputWidth){
                fish2Pano.offsetX -= fish2Pano.outputWidth;
            }else if(fish2Pano.offsetX < -fish2Pano.outputWidth){
                fish2Pano.offsetX += fish2Pano.outputWidth;
            }
        }
        return NO;
    }
    return YES;
}

@end
