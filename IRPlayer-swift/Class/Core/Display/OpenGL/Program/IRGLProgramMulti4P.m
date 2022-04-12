//
//  IRGLProgramMulti4P.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramMulti4P.h"

typedef NS_ENUM(NSInteger, IRGLProgramMultiMode){
    IRGLProgramMultiModeMultiDisplay,
    IRGLProgramMultiModeSingleDisplay
};

@implementation IRGLProgramMulti4P {
    IRGLProgram2D *touchedProgram;
    IRGLProgramMultiMode displayMode;
}

-(instancetype)initWithPrograms:(NSArray*)programs withViewprotRange:(CGRect)viewprotRange{
    if(self = [super initWithPrograms:programs withViewprotRange:viewprotRange]){
        
    }
    return self;
}

-(BOOL)touchedInProgram:(CGPoint)touchedPoint{
    BOOL touchedInProgram = NO;
    touchedProgram = nil;
    for(IRGLProgram2D *program in _programs){
        BOOL touched = [program touchedInProgram:touchedPoint];
        if(touched)
            touchedProgram = program;
        touchedInProgram |= touched;
    }
    return touchedInProgram;
}

-(void)dispatchViewprotRange:(CGRect)viewprotRange resetTransform:(BOOL)resetTransform{
    for(int i = 0; i < [_programs count]; i++){
        IRGLProgram2D *program = [_programs objectAtIndex:i];
        
        if(displayMode == IRGLProgramMultiModeMultiDisplay){
            float viewportWidth = viewprotRange.size.width/2.0;
            float viewportHeight = viewprotRange.size.height/2.0;
            
            [program setViewprotRange:CGRectMake(i%2 * viewportWidth, i/2 * viewportHeight, viewportWidth, viewportHeight) resetTransform:resetTransform];
            
        }else if(displayMode == IRGLProgramMultiModeSingleDisplay){
            float viewportWidth = viewprotRange.size.width;
            float viewportHeight = viewprotRange.size.height;
            
            if(program == touchedProgram)
                [program setViewprotRange:CGRectMake(0, 0, viewportWidth, viewportHeight) resetTransform:NO];
            else
                [program setViewprotRange:CGRectMake(0, 0, 0, 0) resetTransform:NO];
        }
    }
}

-(void)setDefaultScale:(float)scale{
    if(!touchedProgram)
        return;
    
    IRGLProgram2D *program = touchedProgram;
    [program setDefaultScale:scale];
}

-(void) didPanByDegreeX:(float)degreex degreey:(float)degreey{
    if(!touchedProgram)
        return;
    
    if(displayMode == IRGLProgramMultiModeSingleDisplay){
        IRGLProgram2D *program = touchedProgram;
        [program.tramsformController scrollByDegreeX:degreex degreey:degreey];
    }
}

-(void) didPanBydx:(float)dx dy:(float)dy{
    if(!touchedProgram)
        return;
    IRGLProgram2D *program = touchedProgram;
    [program.tramsformController scrollByDx:dx dy:dy];
}

-(void)didPinchByfx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float)dsy{
    if(!touchedProgram)
        return;
    IRGLProgram2D *program = touchedProgram;
    float scaleX = [program.tramsformController getScope].scaleX * dsx;
    float scaleY = [program.tramsformController getScope].scaleY * dsy;
    
    [program didPinchByfx:fx - program.viewprotRange.origin.x fy:fy - program.viewprotRange.origin.y sx:scaleX sy:scaleY];
}

-(void)didPinchByfx:(float)fx fy:(float)fy sx:(float)sx sy:(float)sy{
    if(!touchedProgram)
        return;
    IRGLProgram2D *program = touchedProgram;
    [program didPinchByfx:fx - program.viewprotRange.origin.x fy:fy - program.viewprotRange.origin.y sx:sx sy:sy];
    
}

-(void)didRotate:(float)rotateRadians{
    if(!touchedProgram)
        return;
    IRGLProgram2D *program = touchedProgram;
    [program didRotate:rotateRadians];
}

-(void)didDoubleTap{
    if(!touchedProgram)
        return;
    IRGLProgram2D *program = touchedProgram;
    if(self.doResetToDefaultScaleBlock){
        if(self.doResetToDefaultScaleBlock(self))
            [program didDoubleTap];
    }else if(!CGPointEqualToPoint(CGPointMake([program.tramsformController getScope].scaleX, [program.tramsformController getScope].scaleY), program.tramsformController.getDefaultTransformScale)){
        [program didDoubleTap];
        return;
    }
    
    float viewportWidth = self.viewprotRange.size.width;
    float viewportHeight = self.viewprotRange.size.height;
    
    if(displayMode == IRGLProgramMultiModeMultiDisplay)
        displayMode = IRGLProgramMultiModeSingleDisplay;
    else if(displayMode == IRGLProgramMultiModeSingleDisplay)
        displayMode = IRGLProgramMultiModeMultiDisplay;
    
    for(int i = 0; i < [_programs count]; i++){
        IRGLProgram2D *program = [_programs objectAtIndex:i];
        if(displayMode == IRGLProgramMultiModeMultiDisplay){
            [self setViewprotRange:self.viewprotRange resetTransform:NO];
        }else if(displayMode == IRGLProgramMultiModeSingleDisplay){
            if(program == touchedProgram)
                [program setViewprotRange:CGRectMake(0, 0, viewportWidth, viewportHeight) resetTransform:NO];
            else
                [program setViewprotRange:CGRectMake(0, 0, 0, 0) resetTransform:NO];
        }
    }
}

@end
