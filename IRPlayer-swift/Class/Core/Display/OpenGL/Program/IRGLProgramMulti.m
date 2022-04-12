//
//  IRGLProgramMulti.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLProgramMulti.h"

@implementation IRGLProgramMulti

- (instancetype)initWithPrograms:(NSArray*)programs withViewprotRange:(CGRect)viewprotRange {
    if(self = [self init]){
        
        _programs = [programs copy];
        
        [self setViewprotRange:viewprotRange];
    }
    return self;
}

- (void)setContentMode:(IRGLRenderContentMode)contentMode {
    [super setContentMode:contentMode];
    for(IRGLProgram2D *program in _programs){
        [program setContentMode:contentMode];
    }
}

- (void)updateTextureWidth:(NSUInteger)w height:(NSUInteger)h {
    [super updateTextureWidth:w height:h];
    for(IRGLProgram2D *program in _programs){
        [program updateTextureWidth:w height:h];
    }
}

- (void)setRenderer:(id<IRGLRender>)renderer {
    [super setRenderer:renderer];
    for(IRGLProgram2D *program in _programs){
        [program setRenderer:renderer];
    }
}

-(BOOL)loadShaders{
    BOOL loadShadersSuccess = YES;
    for(IRGLProgram2D *program in _programs){
        loadShadersSuccess &= [program loadShaders];
    }
    return loadShadersSuccess;
}

-(BOOL)touchedInProgram:(CGPoint)touchedPoint{
    BOOL touchedInProgram = NO;
    for(IRGLProgram2D *program in _programs){
        touchedInProgram |= [program touchedInProgram:touchedPoint];
    }
    return touchedInProgram;
}

-(void)setViewprotRange:(CGRect)viewprotRange resetTransform:(BOOL)resetTransform{
    [super setViewprotRange:viewprotRange resetTransform:resetTransform];
    
    [self dispatchViewprotRange:viewprotRange resetTransform:resetTransform];
}

-(void)dispatchViewprotRange:(CGRect)viewprotRange resetTransform:(BOOL)resetTransform{
    for(IRGLProgram2D *program in _programs){
        [program setViewprotRange:viewprotRange resetTransform:resetTransform];
    }
}

-(void) setRenderFrame:(IRFFVideoFrame*)frame{
    for(IRGLProgram2D *program in _programs){
        [program setRenderFrame:frame];
    }
}

-(void) setModelviewProj:(GLKMatrix4) modelviewProj{
    for(IRGLProgram2D *program in _programs){
        [program setModelviewProj:modelviewProj];
    }
}

-(BOOL) prepareRender{
    BOOL prepareRenderSuccess = YES;
    for(IRGLProgram2D *program in _programs){
        prepareRenderSuccess &= [program prepareRender];
    }
    return prepareRenderSuccess;
}

-(void) render{
    for(IRGLProgram2D *program in _programs){
        [program render];
    }
}

-(void) releaseProgram{
    for(IRGLProgram2D *program in _programs){
        [program releaseProgram];
    }
}

-(CGSize) getOutputSize{
    return CGSizeZero;
}

-(void)setDefaultScale:(float)scale{
    for(IRGLProgram2D *program in _programs){
        [program setDefaultScale:scale];
    }
}

-(void) didPanByDegreeX:(float)degreex degreey:(float)degreey{
    for(IRGLProgram2D *program in _programs){
        [program.tramsformController scrollByDegreeX:degreex degreey:degreey];
    }
}

-(void) didPanBydx:(float)dx dy:(float)dy{
    for(IRGLProgram2D *program in _programs){
        [program.tramsformController scrollByDx:dx dy:dy];
    }
}

-(void)didPinchByfx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float)dsy{
    for(IRGLProgram2D *program in _programs){
        float scaleX = [program.tramsformController getScope].scaleX * dsx;
        float scaleY = [program.tramsformController getScope].scaleY * dsy;
        
        [program didPinchByfx:fx fy:fy sx:scaleX sy:scaleY];
    }
}

-(void)didPinchByfx:(float)fx fy:(float)fy sx:(float)sx sy:(float)sy{
    for(IRGLProgram2D *program in _programs){
        [program didPinchByfx:fx fy:fy sx:sx sy:sy];
    }
}

-(void)didRotate:(float)rotateRadians{
    for(IRGLProgram2D *program in _programs){
        [program didRotate:rotateRadians];
    }
}

-(void)didDoubleTap{
    for(IRGLProgram2D *program in _programs){
        [program didDoubleTap];
    }
}

-(void)setDoResetToDefaultScaleBlock:(IRGLProgram2DResetScaleBlock)doResetToDefaultScaleBlock{
    [super setDoResetToDefaultScaleBlock:doResetToDefaultScaleBlock];
    
    for(IRGLProgram2D *program in _programs){
        program.doResetToDefaultScaleBlock = doResetToDefaultScaleBlock;
    }
}

@end
