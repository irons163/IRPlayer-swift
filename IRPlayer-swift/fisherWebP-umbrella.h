//
//  fisherWebP-umbrella.h
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/28.
//  Copyright © 2022 Phil. All rights reserved.
//

#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif



//#import "libavcodample.h"
//#import "libswscale/swscale.ec/avcodec.h"
//#import "libavdevice/avdevice.h"
//#import "libavfilter/avfilter.h"
//#import "libavformat/avformat.h"
//#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import <IRPlayer_swift/IRSensor.h>
#import "IRSmoothScrollController.h"
#import "IRGLRenderModeFactory.h"
#import "IRGLRenderMode.h"
#import "IRFFVideoInput.h"
//#import "IRPlayerAction.h"
#import "IRPLFView.h"
#import "IRGLRenderMode.h"
#import "IRPLFImage.h"
//#import "IRAVPlayer.h"
//#import "IRFFPlayer.h"
#import "IRGLGestureController.h"
//#import "IRFFPlayer.h"
#import "IRFFTools.h"
#import "IRGLRenderMode2D.h"
#import "IRGLRenderMode2DFisheye2Pano.h"
#import "IRGLRenderMode3DFisheye.h"
#import "IRGLRenderModeMulti4P.h"
#import "IRGLRenderNV12.h"
#import "IRFisheyeParameter.h"
#import <CoreMotion/CoreMotion.h>
#import "IRFFCVYUVVideoFrame.h"
#import "IRGLSupportPixelFormat.h"

#import "IRFFAudioFrame.h"
#import "IRFFTrack.h"
#import "IRFFPacketQueue.h"
#import "IRFFFrameQueue.h"
#import "IRFFFramePool.h"
#import "IRFFAVYUVVideoFrame.h"
#import "IRFFMpegErrorUtil.h"
