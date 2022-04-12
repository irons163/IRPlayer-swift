//
//  IRGLTransformController3DFisheye.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLTransformController3DFisheye.h"

@implementation IRGLTransformController3DFisheye {
    IRGLScope3D *scope;
    TiltType defaultType;
}
@synthesize viewMatrix;

const float CAMERA_RADIUS = 120.0f;
const float DEFAULT_FOV = 60.0f;
const float DRAG_FRICTION = 0.15f;
const float INITIAL_PITCH_DEGREES = 0;

-(IRGLScope3D*)getScope{
    return scope;
}

-(IRGLScopeRange *)getScopeRange{
    return _scopeRange;
}

-(void)setScopeRange:(IRGLScopeRange *)scopeRange{
    _scopeRange = scopeRange;
    
    [self setupScope:_scopeRange];
    [self setupScope:scope.tiltType degree:scope.panDegree lat:scope.lat lng:scope.lng sx:scope.scaleX sy:scope.scaleY];
    [self updateVertices];
}

-(void)setScaleRange:(IRGLScaleRange *)scaleRange{
    _scaleRange = scaleRange;
    
    [self updateToDefault];
}

-(instancetype)initWithViewportWidth:(int)width viewportHeight:(int)height tileType:(TiltType)type{
    if(self = [super init]){
        defaultType = type;
        scope = [[IRGLScope3D alloc] init];
        scope.tiltType = defaultType;
        _scopeRange = [self getScopeRangeOf:scope.tiltType];
        
        scope.W = width;
        scope.H = height;
        _defaultTransformScaleX = scope.scaleX;
        _defaultTransformScaleY = scope.scaleY;
        
        float aspectRatio = (float) width / height;
        float fovyRadians = fov * M_PI / 180.0;
        projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0f, 1000.0f);
        viewMatrix = GLKMatrix4Identity;
        [self setupTilt:scope.tiltType];
        
        rc = CAMERA_RADIUS;
        fov = DEFAULT_FOV;
        tanbase = (float)tan(fov / 2 * M_PI / 180.0);
        
        [self resetViewport:width :height resetTransform:YES];
    }
    return self;
}

-(IRGLScopeRange*) getScopeRangeOf:(TiltType) type {
    switch(type){
        case TILT_UP: return [[IRGLScopeRange alloc] initWithMinLat:-80 maxLat:80 minLng:-75 maxLng:75 defaultLat:0 defaultLng:0];
        case TILT_TOWARD: return [[IRGLScopeRange alloc] initWithMinLat:0 maxLat:80 minLng:-180 maxLng:180 defaultLat:80 defaultLng:-90];
        case TILT_BACKWARD: return [[IRGLScopeRange alloc] initWithMinLat:-85 maxLat:-20 minLng:-180 maxLng:180 defaultLat:-80 defaultLng:90];
        default: ;
    }
    return nil;
}

-(GLKMatrix4)getModelViewProjectionMatrix{
    GLKMatrix4 mv = GLKMatrix4Multiply(viewMatrix, modelMatrix); // VM = V x M;
    GLKMatrix4 mvp = GLKMatrix4Multiply(projectMatrix, mv); // PVM = P x VM;
    return mvp;
}

-(CGPoint)getDefaultTransformScale{
    return CGPointMake(_defaultTransformScaleX, _defaultTransformScaleY);
}

-(void) updateToDefault{
    [self updateByFx:0 fy:0 sx:_defaultTransformScaleX * _scaleRange.defaultScaleX sy:_defaultTransformScaleY * _scaleRange.defaultScaleY renew:NO];
}

-(void)scrollByDegreeX:(float)degreex degreey:(float)degreey{
    [self scrollByDx:degreex / DRAG_FRICTION dy:degreey / DRAG_FRICTION];
}

-(void) updateByFx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy
{
    [self updateByFx:fx fy:fy sx:sx sy:sy renew:NO];
}

-(void) updateByFx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy renew:(BOOL)renew
{
    float oldscale = scope.scaleX;
    if(sx <= 1.0){
        scope.scaleX = 1;
        scope.scaleY = 1;
    }
    else {
        float s2 = sx > _scaleRange.maxScaleX? _scaleRange.maxScaleX: sx;
        scope.scaleX = s2;
        scope.scaleY = s2;
    }
    
    if(oldscale != scope.scaleX){
        double newfov = atan((double)tanbase / scope.scaleX) * 2;
        fov = newfov * (180 / M_PI);
        float aspectRatio = (float)scope.W / scope.H;
        float fovyRadians = fov * M_PI / 180.0;
        projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0f, 1000.0f);
        [self updateVertices];
        return;
    }else if(renew){
        [self updateVertices];
        return;
    }
}

-(void) scrollByDx:(float)dx dy:(float)dy
{
    if(scope.W == 0 || scope.H == 0){
        if(self.delegate)
            [self.delegate didScrollWithStatus:IRGLTransformControllerScrollFail withTramsformController:self];
        return;
    }
    
    float oldLng = scope.lng;
    float oldLat = scope.lat;
    
    scope.lng = -dx * DRAG_FRICTION + scope.lng;
    scope.lat = -dy * DRAG_FRICTION + scope.lat;
    
    IRGLTransformControllerScrollStatus status = 0;
    
    if(MIN(_scopeRange.maxLng, scope.lng) == _scopeRange.maxLng){
        status |= IRGLTransformControllerScrollToMaxX;
    }else if(MAX(_scopeRange.minLng, scope.lng) == _scopeRange.minLng){
        status |= IRGLTransformControllerScrollToMinX;
    }
    
    if(MIN(_scopeRange.maxLat, scope.lat) == _scopeRange.maxLat){
        status |= IRGLTransformControllerScrollToMaxY;
    }else if(MAX(_scopeRange.minLat, scope.lat) == _scopeRange.minLat){
        status |= IRGLTransformControllerScrollToMinY;
    }
    
    BOOL doScrollHorizontal = YES;
    BOOL doScrollVertical = YES;
    
    if(self.delegate){
        doScrollHorizontal = [self.delegate doScrollHorizontalWithStatus:status withTramsformController:self];
        doScrollVertical = [self.delegate doScrollVerticalWithStatus:status withTramsformController:self];
        
        if(!doScrollHorizontal){
            status &= ~IRGLTransformControllerScrollToMinX;
            status &= ~IRGLTransformControllerScrollToMaxX;
            scope.lng = oldLng;
        }
        if(!doScrollVertical){
            status &= ~IRGLTransformControllerScrollToMinY;
            status &= ~IRGLTransformControllerScrollToMaxY;
            scope.lat = oldLat;
        }
    }
    
    if(doScrollHorizontal || doScrollVertical)
        [self updateVertices];
    
    if(self.delegate)
        [self.delegate didScrollWithStatus:status withTramsformController:self];
}

-(void) rotate:(float) degree {
    if(scope.tiltType != TILT_UP)
        return;
    float totaldegree = scope.panDegree + degree;
    return [self setupScope:scope.tiltType degree:totaldegree lat:scope.lat lng:scope.lng sx:scope.scaleX sy:scope.scaleY];
}

-(void)setupScope:(IRGLScopeRange*)newRange{
    _scopeRange = newRange;
    scope.lat = newRange.defaultLat;
    scope.lng = newRange.defaultLng;
}

-(void)setupTilt:(TiltType) type{
    
    switch(type){
        case TILT_UP:
            modelMatrix = GLKMatrix4MakeRotation(INITIAL_PITCH_DEGREES * M_PI / 180.0 ,1, 0, 0);
            break;
        case TILT_TOWARD:
            modelMatrix = GLKMatrix4MakeRotation(-90 * M_PI / 180.0 ,0, 0, 1);
            break;
        case TILT_BACKWARD:
            modelMatrix = GLKMatrix4MakeRotation(90 * M_PI / 180.0 ,0, 0, 1);
            break;
        default:
            break;
    }
    
    scope.tiltType = type;
    
    //    _scopeRange = [self getScopeRangeOf:type];
}

-(void) setupScope:(TiltType) type degree:(float) degree lat:( float) lat lng:(float) lng sx:(float) sx sy:(float) sy
{
    if(scope.tiltType == TILT_UP){
        float newdegree = MAX(-180, MIN(180, degree));
        if(newdegree != scope.panDegree){
            float degree2 = newdegree - scope.panDegree;
            modelMatrix = GLKMatrix4Rotate(modelMatrix, degree2 * M_PI / 180.0 ,1, 0, 0);
            scope.panDegree = newdegree;
        }
    }
    scope.lat = lat;
    scope.lng = lng;
    
    return [self updateByFx:0 fy:0 sx:sx sy:sy renew:YES];
}

- (void) reset {
    scope.W = scope.H = 0;
    scope.scaleX = scope.scaleY = 1.0f;
    scope.panDegree = scope.lat = scope.lng = 0.0f;
    scope.tiltType = defaultType;
//    fov = DEFAULT_FOV;
    _defaultTransformScaleX = scope.scaleX;
    _defaultTransformScaleY = scope.scaleY;
    
    //    [self setupScope:scope.tiltType degree:scope.panDegree lat:scope.lat lng:scope.lng sx:scope.scaleX sy:scope.scaleY];
}

- (void) resetViewport:(int) w :(int) h resetTransform:(BOOL)resetTransform {
    float oldDefaultScaleX = _defaultTransformScaleX;
    float oldDefaultScaleY = _defaultTransformScaleY;
    float oldTiltType = scope.tiltType;;
    
    if(resetTransform){
        [self reset];
        [self setupScope:_scopeRange];
    }
    
    scope.W = w;
    scope.H = h;
    _defaultTransformScaleX = oldDefaultScaleX;
    _defaultTransformScaleY = oldDefaultScaleY;
    float aspectRatio = (float)scope.W / scope.H;
    float fovyRadians = fov * M_PI / 180.0;
    projectMatrix = GLKMatrix4MakePerspective(fovyRadians, aspectRatio, 1.0f, 1000.0f);
    viewMatrix = GLKMatrix4Identity;
    if(oldTiltType!=scope.tiltType)
        [self setupTilt:scope.tiltType];
    
    [self setupScope:scope.tiltType degree:scope.panDegree lat:scope.lat lng:scope.lng sx:scope.scaleX sy:scope.scaleY];
    
    [self updateVertices];
}

- (void)updateVertices
{
    while(scope.lat > 90)
        scope.lat = scope.lat - 180;
    while(scope.lat <= -90)
        scope.lat = 180 + scope.lat;
    scope.lat = MAX(_scopeRange.minLat, MIN(_scopeRange.maxLat - fov / 2, scope.lat));
    while(scope.lng > 180)
        scope.lng = scope.lng - 360;
    while(scope.lng <= -180)
        scope.lng = 360 + scope.lng;
    scope.lng = MAX(_scopeRange.minLng, MIN(_scopeRange.maxLng, scope.lng));
    
    float lng = scope.lng + 180;
    float phi = (90 - scope.lat) * M_PI / 180.0;
    float theta = lng * M_PI / 180.0;
    
    camera[0] = (float)(rc * sin(phi) * cos(theta));
    camera[1] = (float)(rc * cos(phi));
    camera[2] = (float)(rc * sin(phi) * sin(theta));
    
    viewMatrix = GLKMatrix4MakeLookAt(camera[0], camera[1], camera[2],
                                      0, 0, 0,
                                      0, 1, 0);
}

@end
