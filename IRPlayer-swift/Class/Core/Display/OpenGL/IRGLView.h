//
//  IRGLView.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IRGLSupportPixelFormat.h"
//#import "IRPlayerImp.h"
#import "IRFFDecoder.h"

@class IRGLRenderMode;
@class IRGLViewSimulateDeviceShiftController;
@class IRGLView;
@class IRFFVideoFrame;
@class IRMovieDecoder;
@class VideoDecoder;
@class IRAVPlayer;

@class IRPlayerImp;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRDisplayRendererType) {
    IRDisplayRendererTypeEmpty,
    IRDisplayRendererTypeAVPlayerLayer,
    IRDisplayRendererTypeAVPlayerPixelBufferVR,
    IRDisplayRendererTypeFFmpegPexelBuffer,
    IRDisplayRendererTypeFFmpegPexelBufferVR,
};

typedef NS_ENUM(NSInteger, IRRenderMode){
    Normal_2D, //default
    Fisheye_Pano,
    Fisheye_Persp,
    Fisheye_Persp_4P
};

//@protocol IRGLViewDelegate
//
//@optional
//- (void)glViewWillBeginDragging:(IRGLView *)glView;
//- (void)glViewDidEndDragging:(IRGLView *)glView willDecelerate:(BOOL)decelerate;
//- (void)glViewDidEndDecelerating:(IRGLView *)glView;
//- (void)glViewDidScrollToBounds:(IRGLView *)glView;
//- (void)glViewWillBeginZooming:(IRGLView *)glView;
//- (void)glViewDidEndZooming:(IRGLView *)glView atScale:(CGFloat)scale;
//@end

@interface IRGLView : UIView<IRFFDecoderVideoOutput>

- (id)initWithFrame:(CGRect)frame
            decoder:(IRMovieDecoder *) decoder;
- (id)initWithFrame:(CGRect)frame
            withPlayer:(IRPlayerImp *)abstractPlayer;
- (void)render:(nullable IRFFVideoFrame *) frame;
- (void)setDecoder:(VideoDecoder *) decoder;
- (void)updateViewPort:(float)scale;
- (void)updateScopeByFx:(float)fx fy:(float)fy dsx:(float)dsx dsy:(float) dsy;
- (void)scrollByDx:(float)dx dy:(float)dy;
- (void)shiftDegreeX:(float)degreeX degreeY:(float)degreeY;
- (void)setRenderModes:(NSArray<IRGLRenderMode*>*) modes;
- (NSArray*)getRenderModes;
- (IRGLRenderMode*)getCurrentRenderMode;
- (BOOL)chooseRenderMode:(IRGLRenderMode*)mode withImmediatelyRenderOnce:(BOOL)immediatelyRenderOnce;
- (void)clearCanvas;
- (void)doSnapShot;
- (void)closeGLView;
//@property (weak) id<IRGLViewDelegate> delegate;
@property (nonatomic) IRPixelFormat pixelFormat;
@property BOOL doubleTapEnable;
@property BOOL swipeEnable;
@property (nonatomic, weak) IRAVPlayer *avplayer;
@property (nonatomic, assign) CGFloat aspect;
@property (nonatomic, assign) IRDisplayRendererType rendererType;
//@property (nonatomic, strong) SGFingerRotation * fingerRotation;

- (void)initDefaultValue;
- (void)initModes;
- (void)reloadGravityMode;
- (void)cleanEmptyBuffer;
//- (void)reloadIRAVPlayer;
- (void)reloadViewFrame;
- (void)updateFrameFromParent:(CGRect)frame;

@end

NS_ASSUME_NONNULL_END
