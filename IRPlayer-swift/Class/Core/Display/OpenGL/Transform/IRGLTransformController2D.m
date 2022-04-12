//
//  IRGLTransformController2D.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLTransformController2D.h"

@implementation IRGLTransformController2D{
    IRGLScope2D *scope;
    GLKMatrix4 modelviewProj;
    float unitX, unitY;
}

-(IRGLScope2D*)getScope{
    return scope;
}

- (void)setScopeRange:(IRGLScopeRange *)scopeRange{
    _scopeRange = scopeRange;
    //    scope.offsetX = -[self getScope].W/2.0;
    //    scope.offsetY = -[self getScope].H/2.0;
    
    [self scrollByDegreeX:scopeRange.defaultLng degreey:scopeRange.defaultLat];
}

-(void)setScaleRange:(IRGLScaleRange *)scaleRange{
    _scaleRange = scaleRange;
    
    [self updateToDefault];
}

-(instancetype)initWithViewportWidth:(int)width viewportHeight:(int)height{
    if(self = [super init]){
        
        maxX0 = 0.0f, maxY0 = 0.0f, rW = 1.0f, rH = 1.0f;
        scope = [[IRGLScope2D alloc] init];
        scope.W = width;
        scope.H = height;
        _defaultTransformScaleX = scope.scaleX;
        _defaultTransformScaleY = scope.scaleY;
        
        modelviewProj = GLKMatrix4MakeOrtho(-1.0f , 1.0f , -1.0f, 1.0f, -1.0f, 1.0f);
    }
    return self;
}

-(void) setupDefaultTransformScaleX:(float)defaultTransformScaleX transformScaleY:(float)defaultTransformScaleY{
    _defaultTransformScaleX = defaultTransformScaleX;
    _defaultTransformScaleY = defaultTransformScaleY;
    
    if (_defaultTransformScaleX > _scaleRange.maxScaleX) {
        _scaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:_scaleRange.minScaleX minScaleY:_scaleRange.minScaleY maxScaleX:_defaultTransformScaleX maxScaleY:_scaleRange.maxScaleY defaultScaleX:_scaleRange.defaultScaleX defaultScaleY:_scaleRange.defaultScaleY];
    }
    
    if (_defaultTransformScaleY > _scaleRange.maxScaleY) {
        _scaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:_scaleRange.minScaleX minScaleY:_scaleRange.minScaleY maxScaleX:_scaleRange.maxScaleX maxScaleY:_defaultTransformScaleY defaultScaleX:_scaleRange.defaultScaleX defaultScaleY:_scaleRange.defaultScaleY];
    }
}

-(CGPoint)getDefaultTransformScale{
    return CGPointMake(_defaultTransformScaleX, _defaultTransformScaleY);
}

-(GLKMatrix4)getModelViewProjectionMatrix{
    return modelviewProj;
}

-(void) updateToDefault{
    [self updateByFx:scope.W/2.0 fy:scope.H/2.0 sx:_defaultTransformScaleX * _scaleRange.defaultScaleX sy:_defaultTransformScaleY * _scaleRange.defaultScaleY];
}

-(void)scrollByDegreeX:(float)degreex degreey:(float)degreey{
    //    float maxContentOffsetX = [self getScope].W;
    //    float maxContentOffsetY = [self getScope].H;
    float maxContentOffsetX = [self getScope].W * [self getScope].scaleX;
    float maxContentOffsetY = [self getScope].H * [self getScope].scaleY;
    //    float maxContentOffsetX = [self getScope].W * [self getScope].scaleX / [UIScreen mainScreen].scale;
    //    float maxContentOffsetY = [self getScope].H * [self getScope].scaleY / [UIScreen mainScreen].scale;
    
    float wideDegreeX = _scopeRange.maxLng - _scopeRange.minLng;
    float wideDegreeY = _scopeRange.maxLat - _scopeRange.minLat;
    
    if(wideDegreeX == 0){
        unitX = 0;
    }else{
        unitX = (maxContentOffsetX) / wideDegreeX;
    }
    
    if(wideDegreeY == 0){
        unitY = 0;
    }else{
        unitY = (maxContentOffsetY) / wideDegreeY;
    }
    
    [self scrollByDx:degreex * unitX dy:degreey * unitY];
}

-(void) updateByFx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy
{
    IRGLScope2D *scope2d = (IRGLScope2D*)scope;
    if(scope2d.W == 0 || scope2d.H == 0)
        return;
    
    float scaleX = sx;
    float scaleY = sy;
    
    float newScaleX = scaleX;
    float newScaleY = scaleY;
    
    if(scaleX < 1.0 && scaleY < 1.0){
        if(scaleX < scaleY){
            newScaleY = 1.0;
            newScaleX = [self getScope].scaleX / ([self getScope].scaleY / newScaleY);
        }else{
            newScaleX = 1.0;
            newScaleY = [self getScope].scaleY / ([self getScope].scaleX / newScaleX);
        }
    } else if(scaleX > _scaleRange.maxScaleX || scaleY > _scaleRange.maxScaleY){
        if(scaleX < scaleY){
            newScaleY = _scaleRange.maxScaleY;
            newScaleX = [self getScope].scaleX / ([self getScope].scaleY / newScaleY);
        }else{
            newScaleX = _scaleRange.maxScaleX;
            newScaleY = [self getScope].scaleY / ([self getScope].scaleX / newScaleX);
        }
    }
    
    float newx0 = scope2d.offsetX + fx * (newScaleX - scope2d.scaleX) / (newScaleX * scope2d.scaleX);
    float newy0 = scope2d.offsetY + fy * (newScaleY - scope2d.scaleY) / (newScaleY * scope2d.scaleY);
    rW = newScaleX / scope2d.W;
    rH = newScaleY / scope2d.H;
    
    if(newScaleX >= 1.0){
        maxX0 = (float)scope2d.W - 1 / rW;
    }else{
        maxX0 = 0;
    }
    
    if(newScaleY >= 1.0){
        maxY0 = (float)scope2d.H - 1 / rH;
    }else{
        maxY0 = 0;
    }
    
    if(newx0 < 0.0f)
        newx0 = 0.0f;
    else if(newx0 > maxX0)
        newx0 = maxX0;
    if(newy0 < 0.0f)
        newy0 = 0.0f;
    else if(newy0 > maxY0)
        newy0 = maxY0;
    
    scope2d.offsetX = newx0;
    scope2d.offsetY = newy0;
    scope2d.scaleX = newScaleX;
    scope2d.scaleY = newScaleY;
    [self updateVertices];
    NSLog(@"%f %f %f %f",scope2d.offsetX,
          scope2d.offsetY,
          scope2d.scaleX,
          scope2d.scaleY);
}

-(void) scrollByDx:(float)dx dy:(float)dy
{
    if(self.delegate)
        [self.delegate willScrollByDx:dx dy:dy withTramsformController:self];
    
    IRGLScope2D *scope2d = (IRGLScope2D*)scope;
    if(scope2d.W == 0 || scope2d.H == 0){
        if(self.delegate)
            [self.delegate didScrollWithStatus:IRGLTransformControllerScrollFail withTramsformController:self];
        return;
    }
    
    IRGLTransformControllerScrollStatus status = 0;
    
    float newx0 = scope2d.offsetX + dx / scope2d.scaleX;
    float newy0 = scope2d.offsetY + dy / scope2d.scaleY;
    if(newx0 < 0.0f){
        newx0 = 0.0f;
        status |= IRGLTransformControllerScrollToMinX;
    }else if(newx0 > maxX0){
        newx0 = maxX0;
        status |= IRGLTransformControllerScrollToMaxX;
    }
    if(newy0 < 0.0f){
        newy0 = 0.0f;
        status |= IRGLTransformControllerScrollToMinY;
    }else if(newy0 > maxY0){
        newy0 = maxY0;
        status |= IRGLTransformControllerScrollToMaxY;
    }
    
    BOOL doScrollHorizontal = YES;
    BOOL doScrollVertical = YES;
    
    if(self.delegate){
        doScrollHorizontal = [self.delegate doScrollHorizontalWithStatus:status withTramsformController:self];
        doScrollVertical = [self.delegate doScrollVerticalWithStatus:status withTramsformController:self];
        
        if(!doScrollHorizontal){
            status &= ~IRGLTransformControllerScrollToMinX;
            status &= ~IRGLTransformControllerScrollToMaxX;
        }
        if(!doScrollVertical){
            status &= ~IRGLTransformControllerScrollToMinY;
            status &= ~IRGLTransformControllerScrollToMaxY;
        }
    }
    
    if(doScrollHorizontal)
        scope2d.offsetX = newx0;
    if(doScrollVertical)
        scope2d.offsetY = newy0;
    if(doScrollHorizontal || doScrollVertical)
        [self updateVertices];
    
    //    if(self.delegate)
    //        [self.delegate willScrollByDx:dx dy:dy withTramsformController:self];
    
    if(self.delegate)
        [self.delegate didScrollWithStatus:status withTramsformController:self];
}

-(void) rotate:(float) degree {
    //not support
}

- (void) reset {
    scope.W = scope.H = 0;
    rW = rH = 1.0f;
    scope.scaleX = scope.scaleY = 1.0f;
    scope.offsetX = scope.offsetY = 0.0f;
    maxX0 = maxY0 = 0.0f;
    _defaultTransformScaleX = scope.scaleX;
    _defaultTransformScaleY = scope.scaleY;
}

- (void) resetViewport:(int) w :(int) h resetTransform:(BOOL)resetTransform {
    float oldDefaultScaleX = _defaultTransformScaleX;
    float oldDefaultScaleY = _defaultTransformScaleY;
    _defaultTransformScaleX = oldDefaultScaleX;
    _defaultTransformScaleY = oldDefaultScaleY;
    
    if(resetTransform){
        [self reset];
        scope.W = w;
        scope.H = h;
        [self updateToDefault];
    }else{
        scope.W = w;
        scope.H = h;
        
        float oldrW = rW;
        float oldrH = rH;
        rW = scope.scaleX / scope.W;
        rH = scope.scaleY / scope.H;
        if(scope.scaleX >= 1.0){
            maxX0 = (float)scope.W - 1 / rW;
        }else{
            maxX0 = 0;
        }
        
        if(scope.scaleY >= 1.0){
            maxY0 = (float)scope.H - 1 / rH;
        }else{
            maxY0 = 0;
        }
        
        float newx = scope.offsetX * (oldrW/rW);
        float newy = scope.offsetY * (oldrH/rH);
        scope.offsetX = newx;
        scope.offsetY = newy;
        [self updateVertices];
    }
}

- (void)updateVertices
{
    IRGLScope2D *scope2d = (IRGLScope2D*)scope;
    
    modelviewProj = GLKMatrix4MakeTranslation(scope2d.offsetX * rW * 2 + 1.0f - scope2d.scaleX, scope2d.offsetY * rH * 2 + 1.0f - scope2d.scaleY, 0);
    modelviewProj = GLKMatrix4Scale(modelviewProj, scope2d.scaleX, scope2d.scaleY, 1.0f);
}

@end
