//
//  IRGLProgramFactory.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramFactory.h"
#import "IRGLTransformController2D.h"
#import "IRGLTransformController3DFisheye.h"
#import "IRGLTransformControllerVR.h"
#import "IRGLTransformControllerDistortion.h"
#import "IRGLProjectionOrthographic.h"
#import "IRGLProjectionEquirectangular.h"
#import "IRGLProjectionVR.h"
#import "IRGLProjectionDistortion.h"
#import "IRFisheyeParameter.h"

@implementation IRGLProgramFactory

+(IRGLProgram2D*) createIRGLProgram2DWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    IRGLProgram2D* program = [[IRGLProgram2D alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        program.tramsformController.delegate = program;
    }
    program.mapProjection = [[IRGLProjectionOrthographic alloc] initWithTextureWidth:0 hidth:0];
    return program;
}

+(IRGLProgram2DFisheye2Pano*) createIRGLProgram2DFisheye2PanoWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    IRGLProgram2DFisheye2Pano* program = [[IRGLProgram2DFisheye2Pano alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        program.tramsformController.delegate = program;
        
        IRGLScaleRange* oldScaleRange = program.tramsformController.scaleRange;
        IRGLScaleRange* newScaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:oldScaleRange.minScaleX minScaleY:oldScaleRange.minScaleY maxScaleX:oldScaleRange.maxScaleX * 1.5f maxScaleY:oldScaleRange.maxScaleY * 1.5f defaultScaleX:oldScaleRange.defaultScaleX defaultScaleY:oldScaleRange.defaultScaleY];
        program.tramsformController.scaleRange = newScaleRange;
    }
    program.mapProjection = [[IRGLProjectionOrthographic alloc] initWithTextureWidth:0 hidth:0];
    return program;
}

+(IRGLProgram2DFisheye2Persp*) createIRGLProgram2DFisheye2PerspWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    IRGLProgram2DFisheye2Persp* program = [[IRGLProgram2DFisheye2Persp alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        program.tramsformController.delegate = program;
    }
    program.mapProjection = [[IRGLProjectionOrthographic alloc] initWithTextureWidth:0 hidth:0];
    return program;
}

+(IRGLProgram3DFisheye*) createIRGLProgram3DFisheyeWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    if(!parameter)  {
        parameter = [[IRFisheyeParameter alloc] initWithWidth:0 height:0 up:NO rx:0 ry:0 cx:0 cy:0 latmax:0];
    }else if(![parameter isKindOfClass:[IRFisheyeParameter class]]){
        NSLog(@"createIRGLProgram failed.");
        return nil;
    }
    
    IRFisheyeParameter* fp = (IRFisheyeParameter*)parameter;
    
    IRGLProgram3DFisheye* program = [[IRGLProgram3DFisheye alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController3DFisheye alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height tileType:TILT_BACKWARD];
        program.tramsformController.delegate = program;
        
        IRGLScopeRange* oldScopeRange = program.tramsformController.scopeRange;
        float oldMaxLat = oldScopeRange.maxLat;
        float newMaxLat = (oldMaxLat > 0) ? fp.latmax : fp.latmax - 90.0;
        float newDefaultLat = oldScopeRange.defaultLat;
        if(newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat)
            newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2;
        IRGLScopeRange* newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:oldScopeRange.minLat maxLat:newMaxLat minLng:oldScopeRange.minLng maxLng:oldScopeRange.maxLng defaultLat:newDefaultLat defaultLng:oldScopeRange.defaultLng];
        program.tramsformController.scopeRange = newScopeRange;
        
        IRGLScopeRange* scopeRange = [(IRGLTransformController3DFisheye*)program.tramsformController getScopeRange];
        newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:90];
        [program.tramsformController setScopeRange:newScopeRange];
    }
    program.mapProjection = [[IRGLProjectionEquirectangular alloc] initWithTextureWidth:fp.width height:fp.height centerX:fp.cx centerY:fp.cy radius:fp.ry];
    return program;
}

+(IRGLProgramMulti4P*) createIRGLProgram2DFisheye2Persp4PWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter {
    NSArray* programs_4p = @[
                             [IRGLProgramFactory createIRGLProgram2DFisheye2PerspWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [IRGLProgramFactory createIRGLProgram2DFisheye2PerspWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [IRGLProgramFactory createIRGLProgram2DFisheye2PerspWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [IRGLProgramFactory createIRGLProgram2DFisheye2PerspWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter]
                             ];
    IRGLProgramMulti4P* program = [[IRGLProgramMulti4P alloc] initWithPrograms:programs_4p withViewprotRange:viewprotRange];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        program.tramsformController.delegate = program;
    }
    
    for(int i = 0; i < [programs_4p count]; i++){
        IRGLProgram2DFisheye2Persp* program = programs_4p[i];
        if(i==0)
            [program setTransformX:0 Y:0];
        else if(i==1)
            [program setTransformX:45 Y:-45];
        else if(i==2)
            [program setTransformX:45 Y:180];
        else if(i==3)
            [program setTransformX:45 Y:-90];
    }
    
    return program;
}

+(IRGLProgramMulti4P*) createIRGLProgram3DFisheye4PWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    if (!parameter) {
        parameter = [[IRFisheyeParameter alloc] initWithWidth:0 height:0 up:NO rx:0 ry:0 cx:0 cy:0 latmax:0];
    } else if (![parameter isKindOfClass:[IRFisheyeParameter class]]){
        NSLog(@"createIRGLProgram failed.");
        return nil;
    }
    
    IRFisheyeParameter* fp = (IRFisheyeParameter*)parameter;
    
    NSArray* programs_4p = @[
                             [[IRGLProgram3DFisheye alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [[IRGLProgram3DFisheye alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [[IRGLProgram3DFisheye alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             [[IRGLProgram3DFisheye alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter],
                             ];
    
    IRGLProgramMulti4P* program = [[IRGLProgramMulti4P alloc] initWithPrograms:programs_4p withViewprotRange:viewprotRange];
    if(!program.tramsformController){
        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        program.tramsformController.delegate = program;
    }
    
    id<IRGLProjection> mapProjection = [[IRGLProjectionEquirectangular alloc] initWithTextureWidth:1440 height:1080 centerX:fp.cx centerY:fp.cy radius:fp.ry];
    
    for(int i = 0; i < [programs_4p count]; i++){
        IRGLProgram3DFisheye* program = programs_4p[i];
        if(!program.tramsformController){
            program.tramsformController = [[IRGLTransformController3DFisheye alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height tileType:TILT_BACKWARD];
            program.tramsformController.delegate = program;
            
            IRGLScopeRange* oldScopeRange = program.tramsformController.scopeRange;
            float oldMaxLat = oldScopeRange.maxLat;
            float newMaxLat = (oldMaxLat > 0) ? fp.latmax : fp.latmax - 90.0;
            float newDefaultLat = oldScopeRange.defaultLat;
            if(newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat)
                newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2;
            IRGLScopeRange* newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:oldScopeRange.minLat maxLat:newMaxLat minLng:oldScopeRange.minLng maxLng:oldScopeRange.maxLng defaultLat:newDefaultLat defaultLng:oldScopeRange.defaultLng];
            program.tramsformController.scopeRange = newScopeRange;
        }
        program.mapProjection = mapProjection;
        
        IRGLScopeRange* scopeRange = [(IRGLTransformController3DFisheye*)program.tramsformController getScopeRange];
        IRGLScopeRange* newScopeRange;
        
        if(i==0){
            newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:90];
        }else if(i==1){
            newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:180];
        }else if(i==2){
            newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:270];
        }else if(i==3){
            newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:0];
        }
        
        [program.tramsformController setScopeRange:newScopeRange];
    }
    
    return program;
}

+(IRGLProgramVR*) createIRGLProgramVRWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    IRGLProgramVR* program = [[IRGLProgramVR alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        IRGLTransformControllerVR *transformController = [[IRGLTransformControllerVR alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height tileType:TILT_UP];
        transformController.rc = 1;
        transformController.fov = 30;
        [transformController updateVertices];
        program.tramsformController = transformController;
        program.tramsformController.delegate = program;
//        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
//        program.tramsformController.delegate = program;
//        IRGLScopeRange* oldScopeRange = program.tramsformController.scopeRange;
//        float oldMaxLat = oldScopeRange.maxLat;
//        float newMaxLat = (oldMaxLat > 0) ? fp.latmax : fp.latmax - 90.0;
//        float newDefaultLat = oldScopeRange.defaultLat;
//        if(newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat)
//            newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2;
//        IRGLScopeRange* newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:oldScopeRange.minLat maxLat:oldScopeRange.maxLat minLng:oldScopeRange.minLng maxLng:oldScopeRange.maxLng defaultLat:oldScopeRange.defaultLat defaultLng:oldScopeRange.defaultLng];
//        program.tramsformController.scopeRange = newScopeRange;
        
//        IRGLScopeRange* scopeRange = [(IRGLTransformController3DFisheye*)program.tramsformController getScopeRange];
//        newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:90];
//        [program.tramsformController setScopeRange:newScopeRange];
        IRGLScaleRange* oldScaleRange = program.tramsformController.scaleRange;
        IRGLScaleRange* newScaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:oldScaleRange.minScaleX minScaleY:oldScaleRange.minScaleY maxScaleX:oldScaleRange.maxScaleX * 1.5f maxScaleY:oldScaleRange.maxScaleY * 1.5f defaultScaleX:oldScaleRange.defaultScaleX defaultScaleY:oldScaleRange.defaultScaleY];
        program.tramsformController.scaleRange = newScaleRange;
    }
    program.mapProjection = [[IRGLProjectionVR alloc] initWithTextureWidth:0 hidth:0];
    return program;
}

+(IRGLProgramDistortion*) createIRGLProgramDistortionWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter{
    IRGLProgramDistortion* program = [[IRGLProgramDistortion alloc] initWithPixelFormat:pixelFormat withViewprotRange:viewprotRange withParameter:(IRMediaParameter*)parameter];
    if(!program.tramsformController){
        IRGLTransformControllerDistortion *transformController = [[IRGLTransformControllerDistortion alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height tileType:TILT_UP];
        transformController.rc = 1;
        transformController.fov = 30;
        [transformController updateVertices];
        program.tramsformController = transformController;
        program.tramsformController.delegate = program;
        //        program.tramsformController = [[IRGLTransformController2D alloc] initWithViewportWidth:viewprotRange.size.width viewportHeight:viewprotRange.size.height];
        //        program.tramsformController.delegate = program;
        //        IRGLScopeRange* oldScopeRange = program.tramsformController.scopeRange;
        //        float oldMaxLat = oldScopeRange.maxLat;
        //        float newMaxLat = (oldMaxLat > 0) ? fp.latmax : fp.latmax - 90.0;
        //        float newDefaultLat = oldScopeRange.defaultLat;
        //        if(newDefaultLat > newMaxLat || newDefaultLat < oldScopeRange.minLat)
        //            newDefaultLat = (newMaxLat + oldScopeRange.minLat) / 2;
        //        IRGLScopeRange* newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:oldScopeRange.minLat maxLat:oldScopeRange.maxLat minLng:oldScopeRange.minLng maxLng:oldScopeRange.maxLng defaultLat:oldScopeRange.defaultLat defaultLng:oldScopeRange.defaultLng];
        //        program.tramsformController.scopeRange = newScopeRange;
        
        //        IRGLScopeRange* scopeRange = [(IRGLTransformController3DFisheye*)program.tramsformController getScopeRange];
        //        newScopeRange = [[IRGLScopeRange alloc] initWithMinLat:scopeRange.minLat maxLat:scopeRange.maxLat minLng:scopeRange.minLng maxLng:scopeRange.maxLng defaultLat:-40 defaultLng:90];
        //        [program.tramsformController setScopeRange:newScopeRange];
        IRGLScaleRange* oldScaleRange = program.tramsformController.scaleRange;
        IRGLScaleRange* newScaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:oldScaleRange.minScaleX minScaleY:oldScaleRange.minScaleY maxScaleX:oldScaleRange.maxScaleX * 1.5f maxScaleY:oldScaleRange.maxScaleY * 1.5f defaultScaleX:oldScaleRange.defaultScaleX defaultScaleY:oldScaleRange.defaultScaleY];
        program.tramsformController.scaleRange = newScaleRange;
    }
    program.mapProjection = [[IRGLProjectionVR alloc] initWithTextureWidth:0 hidth:0];
    return program;
}

@end
