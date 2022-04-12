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



#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
