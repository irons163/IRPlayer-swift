//
//  IRFFTools.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFTools.h"
#import "IRFFDecoder.h"

#pragma mark - Util Function

void IRFFLog(void * context, int level, const char * format, va_list args)
{
#if IRFFFFmpegLogEnable
    NSString * message = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:format] arguments:args];
    IRFFFFmpegLog(@"IRFFLog : %@", message);
#endif
}

NSError * IRFFCheckError(int result)
{
    return IRFFCheckErrorCode(result, -1);
}

NSError * IRFFCheckErrorCode(int result, NSUInteger errorCode)
{
    if (result < 0) {
        char * error_string_buffer = malloc(256);
        av_strerror(result, error_string_buffer, 256);
        NSString * error_string = [NSString stringWithFormat:@"ffmpeg code : %d, ffmpeg msg : %s", result, error_string_buffer];
        NSError * error = [NSError errorWithDomain:error_string code:errorCode userInfo:nil];
        return error;
    }
    return nil;
}

double IRFFStreamGetTimebase(AVStream * stream, double default_timebase)
{
    double timebase;
    if (stream->time_base.den > 0 && stream->time_base.num > 0) {
        timebase = av_q2d(stream->time_base);
    } else {
        timebase = default_timebase;
    }
    return timebase;
}

double IRFFStreamGetFPS(AVStream * stream, double timebase)
{
    double fps;
    if (stream->avg_frame_rate.den > 0 && stream->avg_frame_rate.num > 0) {
        fps = av_q2d(stream->avg_frame_rate);
    } else if (stream->r_frame_rate.den > 0 && stream->r_frame_rate.num > 0) {
        fps = av_q2d(stream->r_frame_rate);
    } else {
        fps = 1.0 / timebase;
    }
    return fps;
}

NSDictionary * IRFFFoundationBrigeOfAVDictionary(AVDictionary * avDictionary)
{
    if (avDictionary == NULL) return nil;
    
    int count = av_dict_count(avDictionary);
    if (count <= 0) return nil;
    
    NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
    
    AVDictionaryEntry * entry = NULL;
    while ((entry = av_dict_get(avDictionary, "", entry, AV_DICT_IGNORE_SUFFIX))) {
        @autoreleasepool {
            NSString * key = [NSString stringWithUTF8String:entry->key];
            NSString * value = [NSString stringWithUTF8String:entry->value];
            [dictionary setObject:value forKey:key];
        }
    }
    
    return dictionary;
}

