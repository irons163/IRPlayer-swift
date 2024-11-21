//
//  IRPlayer_swift-Bridging-Header.h
//  IRPlayer-swift
//
//  Created by Phil Chang on 2022/4/28.
//  Copyright © 2022 Phil. All rights reserved.
//

#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
//#import "libavutil/avutil.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
#import "libavutil/dict.h"
#import "libavformat/avformat.h"

#import "IRFFCVYUVVideoFrame.h"
#import "IRGLSupportPixelFormat.h"
#import "IRPlayerMacro.h"
#import "IRFFAudioFrame.h"
