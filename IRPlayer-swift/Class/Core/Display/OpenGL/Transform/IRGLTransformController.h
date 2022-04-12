//
//  IRGLTransformController.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IRGLScope2D.h"
#import <GLKit/GLKMatrix4.h>

NS_ASSUME_NONNULL_BEGIN

@class IRGLTransformController;

typedef NS_OPTIONS(NSUInteger, IRGLTransformControllerScrollStatus) {
    IRGLTransformControllerScrollNone = 0,
    IRGLTransformControllerScrollToMaxX = 1 << 0,
    IRGLTransformControllerScrollToMinX = 1 << 1,
    IRGLTransformControllerScrollToMaxY = 1 << 2,
    IRGLTransformControllerScrollToMinY = 1 << 3,
    IRGLTransformControllerScrollFail = 1 << 4
};

typedef NS_ENUM(NSUInteger, IRGLTransformControllerScrollToBounds) {
    IRGLTransformControllerScrollToBoundsNone,
    IRGLTransformControllerScrollToHorizontalBounds,
    IRGLTransformControllerScrollToVerticalBounds,
    IRGLTransformControllerScrollToHorizontalandVerticalBounds
};

@protocol IRGLTransformControllerDelegate
@optional
-(void) willScrollByDx:(float)dx dy:(float)dy withTramsformController:(IRGLTransformController*) tramsformController;
-(BOOL) doScrollHorizontalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController*) tramsformController;
-(BOOL) doScrollVerticalWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController*) tramsformController;
-(void) didScrollWithStatus:(IRGLTransformControllerScrollStatus)status withTramsformController:(IRGLTransformController*) tramsformController;
@end

@interface IRGLScopeRange : NSObject

@property (readonly) float minLat;
@property (readonly) float maxLat;
@property (readonly) float minLng;
@property (readonly) float maxLng;
@property (readonly) float defaultLat;
@property (readonly) float defaultLng;

-(instancetype)initWithMinLat:(float) minLat maxLat:(float) maxLat minLng:(float) minLng maxLng:(float) maxLng defaultLat:(float) defaultLat defaultLng:(float) defaultLng;

@end

@interface IRGLScaleRange : NSObject

@property (readonly) float minScaleX;
@property (readonly) float minScaleY;
@property (readonly) float maxScaleX;
@property (readonly) float maxScaleY;
@property (readonly) float defaultScaleX;
@property (readonly) float defaultScaleY;

-(instancetype)initWithMinScaleX:(float) minScaleX minScaleY:(float) minScaleY maxScaleX:(float) maxScaleX maxScaleY:(float) maxScaleY defaultScaleX:(float) defaultScaleX defaultScaleY:(float) defaultScaleY;

@end

@interface IRGLWideDegreeRange : NSObject
@property (readonly) float wideDegreeX;
@property (readonly) float wideDegreeY;
@end

@interface IRGLTransformController : NSObject{
    float _defaultTransformScaleX, _defaultTransformScaleY;
    IRGLScopeRange *_scopeRange;
    IRGLScaleRange *_scaleRange;
}

@property (weak) id<IRGLTransformControllerDelegate> delegate;
@property (nonatomic) IRGLScopeRange* scopeRange;
@property (nonatomic) IRGLScaleRange* scaleRange;

-(IRGLScope2D*) getScope;
-(GLKMatrix4) getModelViewProjectionMatrix;
-(void) setupDefaultTransformScaleX:(float)defaultTransformScaleX transformScaleY:(float)defaultTransformScaleY;
-(CGPoint) getDefaultTransformScale;
-(void) updateToDefault;
-(void) updateByFx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy;
-(void) scrollByDx:(float)dx dy:(float)dy;
-(void) scrollByDegreeX:(float)degreex degreey:(float)degreey;
-(void) rotate:(float) degree;
-(void) updateVertices;
-(void) resetViewport:(int) w :(int) h resetTransform:(BOOL)resetTransform;
-(void) reset;
@end

NS_ASSUME_NONNULL_END
