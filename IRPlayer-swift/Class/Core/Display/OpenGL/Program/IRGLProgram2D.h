//
//  IRGLProgram2D.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRGLShaderParams.h"
#import "IRGLRenderBase.h"
#import "IRGLTransformController.h"
#import "IRGLProjection.h"
#import "IRMediaParameter.h"
#import "IRGLSupportPixelFormat.h"
#import "IRGLRenderContentMode.h"

NS_ASSUME_NONNULL_BEGIN

@class IRGLProgram2D;

typedef BOOL (^IRGLProgram2DResetScaleBlock)(IRGLProgram2D *program);

@protocol IRGLProgramDelegate <NSObject>

-(void)didScrollToBounds:(IRGLTransformControllerScrollToBounds)bounds withProgram:(IRGLProgram2D *)program;

@end

@interface IRGLProgram2D : NSObject<IRGLShaderParamsDelegate, IRGLTransformControllerDelegate>{
@protected
    GLuint          _program;
    NSString* vertexShaderString;
    NSString* fragmentShaderString;
    IRPixelFormat _pixelFormat;
    id<IRGLRender> _renderer;
}

@property (nullable, readonly) IRMediaParameter *parameter;
@property (nonatomic) IRGLTransformController *tramsformController;
@property (copy) IRGLProgram2DResetScaleBlock doResetToDefaultScaleBlock;
@property id<IRGLProjection> mapProjection;
@property (weak) id<IRGLProgramDelegate> delegate;
@property (nonatomic) IRGLRenderContentMode contentMode;
@property (nonatomic) CGRect viewprotRange;
@property BOOL shouldUpdateToDefaultWhenOutputSizeChanged;

-(instancetype)initWithPixelFormat:(IRPixelFormat)pixelFormat withViewprotRange:(CGRect)viewprotRange withParameter:(IRMediaParameter*)parameter;
-(BOOL) loadShaders;
-(void) setRenderer:(id<IRGLRender>)renderer;
-(void) setViewprotRange:(CGRect)viewprotRange resetTransform:(BOOL)resetTransform;
-(void) setDefaultScale:(float)scale;
-(CGPoint) getCurrentScale;
-(void) setRenderFrame:(IRFFVideoFrame*)frame;
-(void) setModelviewProj:(GLKMatrix4) modelviewProj;
-(BOOL) prepareRender;
-(void) clearBuffer;
-(CGRect) calculateViewport;
-(void) render;
-(void) releaseProgram;
-(CGSize) getOutputSize;
-(BOOL) touchedInProgram:(CGPoint)touchedPoint;
-(void) didPanBydx:(float)dx dy:(float)dy;
-(void) didPinchByfx:(float)fx fy:(float)fy sx:(float)sx sy:(float) sy;
-(void) didPinchByfx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float)dsy;
-(void) didPanByDegreeX:(float)degreex degreey:(float)degreey;
-(void) didRotate:(float)rotateRadians;
-(void) didDoubleTap;
-(void) updateTextureWidth:(NSUInteger)w height:(NSUInteger)h;
@end

NS_ASSUME_NONNULL_END
