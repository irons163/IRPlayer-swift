//
//  IRGLTransformController.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLTransformController.h"

//#define DEFAULT_WIDE_DEGREE_X 360
//#define DEFAULT_WIDE_DEGREE_Y 180

#define MIN_SCALE 1.0
#define MAX_SCALE 4.0

@implementation IRGLScopeRange

-(instancetype)initWithMinLat:(float) minLat maxLat:(float) maxLat minLng:(float) minLng maxLng:(float) maxLng defaultLat:(float) defaultLat defaultLng:(float) defaultLng{
    if(self = [super init]){
        _defaultLat = defaultLat;
        _defaultLng = defaultLng;
        _minLat = minLat;
        _maxLat = maxLat;
        _minLng = minLng;
        _maxLng = maxLng;
    }
    return self;
}

@end

@implementation IRGLScaleRange

-(instancetype)initWithMinScaleX:(float) minScaleX minScaleY:(float) minScaleY maxScaleX:(float) maxScaleX maxScaleY:(float) maxScaleY defaultScaleX:(float) defaultScaleX defaultScaleY:(float) defaultScaleY{
    if(self = [super init]){
        _minScaleX = minScaleX;
        _minScaleY = minScaleY;
        _maxScaleX = maxScaleX;
        _maxScaleY = maxScaleY;
        _defaultScaleX = defaultScaleX;
        _defaultScaleY = defaultScaleY;
    }
    return self;
}

@end

@implementation WideDegreeRange : NSObject

@end

@implementation IRGLTransformController{
    
}
@synthesize scopeRange = _scopeRange;
@synthesize scaleRange = _scaleRange;

-(instancetype)init{
    if(self = [super init]){
        _scopeRange = [[IRGLScopeRange alloc] initWithMinLat:0 maxLat:0 minLng:0 maxLng:0 defaultLat:0 defaultLng:0];
        _scaleRange = [[IRGLScaleRange alloc] initWithMinScaleX:MIN_SCALE minScaleY:MIN_SCALE maxScaleX:MAX_SCALE maxScaleY:MAX_SCALE defaultScaleX:MIN_SCALE defaultScaleY:MIN_SCALE];
    }
    return self;
}

-(IRGLScope2D*) getScope{
    return nil;
}

- (void)setScopeRange:(IRGLScopeRange *)scopeRange{
    
}

-(void)setScaleRange:(IRGLScaleRange *)scaleRange{
    
}

-(GLKMatrix4) getModelViewProjectionMatrix{
    return GLKMatrix4Identity;
}

-(void) setupDefaultTransformScaleX:(float)defaultTransformScaleX transformScaleY:(float)defaultTransformScaleY{
    
}

-(CGPoint) getDefaultTransformScale{
    return CGPointMake(_defaultTransformScaleX, _defaultTransformScaleY);
}

-(void) updateToDefault{
    
}

-(void)scrollByDegreeX:(float)degreex degreey:(float)degreey{
    
}

-(void) updateByFx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy{
    
}

-(void) scrollByDx:(float)dx dy:(float)dy{
    
}

-(void) rotate:(float) degree{
    
}

-(void) updateVertices{
    
}

-(void) resetViewport:(int) w :(int) h resetTransform:(BOOL)resetTransform{
    
}

-(void) reset{
    
}

@end
