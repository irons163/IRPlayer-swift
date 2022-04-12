//
//  IRFFTools.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRPlayerMacro.h"
#import "avformat.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRFFDecoderErrorCode) {
    IRFFDecoderErrorCodeFormatCreate,
    IRFFDecoderErrorCodeFormatOpenInput,
    IRFFDecoderErrorCodeFormatFindStreamInfo,
    IRFFDecoderErrorCodeStreamNotFound,
    IRFFDecoderErrorCodeCodecContextCreate,
    IRFFDecoderErrorCodeCodecContextSetParam,
    IRFFDecoderErrorCodeCodecFindDecoder,
    IRFFDecoderErrorCodeCodecVideoSendPacket,
    IRFFDecoderErrorCodeCodecAudioSendPacket,
    IRFFDecoderErrorCodeCodecVideoReceiveFrame,
    IRFFDecoderErrorCodeCodecAudioReceiveFrame,
    IRFFDecoderErrorCodeCodecOpen2,
    IRFFDecoderErrorCodeAuidoSwrInit,
};

#pragma mark - Log Config

#define IRFFFFmpegLogEnable     0
#define IRFFSynLogEnable        0
#define IRFFThreadLogEnable     0
#define IRFFPacketLogEnable     0
#define IRFFSleepLogEnable      0
#define IRFFDecodeLogEnable     0
#define IRFFErrorLogEnable      0

#if IRFFFFmpegLogEnable
#define IRFFFFmpegLog(...)       NSLog(__VA_ARGS__)
#else
#define IRFFFFmpegLog(...)
#endif

#if IRFFSynLogEnable
#define IRFFSynLog(...)          NSLog(__VA_ARGS__)
#else
#define IRFFSynLog(...)
#endif

#if IRFFThreadLogEnable
#define IRFFThreadLog(...)       NSLog(__VA_ARGS__)
#else
#define IRFFThreadLog(...)
#endif

#if IRFFPacketLogEnable
#define IRFFPacketLog(...)       NSLog(__VA_ARGS__)
#else
#define IRFFPacketLog(...)
#endif

#if IRFFSleepLogEnable
#define IRFFSleepLog(...)        NSLog(__VA_ARGS__)
#else
#define IRFFSleepLog(...)
#endif

#if IRFFDecodeLogEnable
#define IRFFDecodeLog(...)       NSLog(__VA_ARGS__)
#else
#define IRFFDecodeLog(...)
#endif

#if IRFFErrorLogEnable
#define IRFFErrorLog(...)        NSLog(__VA_ARGS__)
#else
#define IRFFErrorLog(...)
#endif


#pragma mark - Util Function

void IRFFLog(void * context, int level, const char * format, va_list args);

NSError * IRFFCheckError(int result);
NSError * IRFFCheckErrorCode(int result, NSUInteger errorCode);

double IRFFStreamGetTimebase(AVStream * stream, double default_timebase);
double IRFFStreamGetFPS(AVStream * stream, double timebase);

NSDictionary * IRFFFoundationBrigeOfAVDictionary(AVDictionary * avDictionary);

NS_ASSUME_NONNULL_END
