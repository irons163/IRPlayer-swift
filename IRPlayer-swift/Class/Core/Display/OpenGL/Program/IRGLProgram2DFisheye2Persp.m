//
//  IRGLProgram2DFisheye2Persp.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgram2DFisheye2Persp.h"
#import "IRGLFish2PerspShaderParams.h"
#import "IRGLVertexShaderGLSL.h"
#import "IRGLFragmentFish2PerspShaderGLSL.h"

@interface IRGLProgram2DFisheye2Persp(Protected)
-(void)initShaderParams;
@end

@implementation IRGLProgram2DFisheye2Persp{
    IRGLFish2PerspShaderParams *fish2Persp;
    float willScrollX, willScrollY;
    float transformXWhenTouchDown;
}


-(NSString*)vertexShader{
    vertexShaderString = [IRGLVertexShaderGLSL getShardString];
    return vertexShaderString;
}

-(NSString*)fragmentShader{
    fragmentShaderString = [IRGLFragmentFish2PerspShaderGLSL getShardString:_pixelFormat];
    return fragmentShaderString;
}

-(void)initShaderParams{
    fish2Persp = [[IRGLFish2PerspShaderParams alloc] init];
    fish2Persp.delegate = self;
}

-(BOOL)loadShaders
{
    if([super loadShaders]){
        [fish2Persp resolveUniforms:_program];
        return YES;
    }
    return NO;
}

-(void)setRenderFrame:(IRFFVideoFrame*)frame{
    [super setRenderFrame:frame];
    
    if(frame.width != fish2Persp.textureWidth || frame.height != fish2Persp.textureHeight)
        [fish2Persp updateTextureWidth:frame.width height:frame.height];
}

- (BOOL) prepareRender{
    if([super prepareRender]){
        [fish2Persp prepareRender];
        return YES;
    }
    return NO;
}

- (void)setTransformX:(float)x Y:(float)y{
    fish2Persp.transformX = x;
    fish2Persp.transformY = y;
}

//-(BOOL)touchedInProgram:(CGPoint)touchedPoint{
//    transformXWhenTouchDown = fish2Persp.transformX;
//    return [super touchedInProgram:touchedPoint];
//}

-(void)willScrollByDx:(float)dx dy:(float)dy withTramsformController:(IRGLTransformController *)tramsformController{
    willScrollX = dx;
    willScrollY = dy;
}

-(BOOL)doScrollHorizontalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    if(status & IRGLTransformControllerScrollToMaxX || status & IRGLTransformControllerScrollToMinX){
        float moveDegree = -1*(willScrollX * (180.0 / fish2Persp.outputWidth));
        //        if(transformXWhenTouchDown > 0)
        //            moveDegree *= -1;
        fish2Persp.transformY -= moveDegree;
        return NO;
    }
    return YES;
}

-(BOOL)doScrollVerticalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController *)tramsformController{
    if(status & IRGLTransformControllerScrollToMaxY || status & IRGLTransformControllerScrollToMinY){
        fish2Persp.transformX -= (willScrollY * (180.0 / (fish2Persp.fishradiush * 2.0)));
        //        float viewportHalfHeightDegree = fish2Persp.outputHeight /2.0 * (180.0 / (fish2Persp.textureHeight));
        
        if(fish2Persp.transformX > 55){
            fish2Persp.transformX = 55;
        }else if(fish2Persp.transformX < 0){
            fish2Persp.transformX = 0;
        }
        //        if(fish2Persp.transformX > 90 - viewportHalfHeightDegree){
        //            fish2Persp.transformX = 90 - viewportHalfHeightDegree;
        //        }else if(fish2Persp.transformX < 0){
        //            fish2Persp.transformX = 0;
        //        }
        return NO;
    }
    return YES;
}


@end
