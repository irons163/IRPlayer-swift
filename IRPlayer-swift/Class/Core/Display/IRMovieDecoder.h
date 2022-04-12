//
//  IRMovieDecoder.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include "avformat.h"
#include "IRFFFrame.h"
#include "IRFFVideoFrame.h"
#include "IRFFAudioFrame.h"

//@class IRFFFrame;

NS_ASSUME_NONNULL_BEGIN

extern NSString * IRMovieErrorDomain;

typedef enum {
    
    IRMovieErrorNone,
    IRMovieErrorOpenFile,
    IRMovieErrorStreamInfoNotFound,
    IRMovieErrorStreamNotFound,
    IRMovieErrorCodecNotFound,
    IRMovieErrorOpenCodec,
    IRMovieErrorAllocateFrame,
    IRMovieErroSetupScaler,
    IRMovieErroReSampler,
    IRMovieErroUnsupported,
    
} IRMovieError;

typedef enum {
    
    IRFrameFormatRGB,
    IRFrameFormatYUV,
    IRFrameFormatNV12,
    
} IRFrameFormat;

@interface IRVideoFrameRGB : IRFFVideoFrame
@property (readonly, nonatomic) NSUInteger linesize;
@property (readonly, nonatomic, strong) NSData *rgb;
- (UIImage *) asImage;
@end

@protocol IRMovieDecoderDelegate <NSObject>
@optional
- (AVFormatContext*) attachedAVFormatContext;
- (void) receivedMetadata:(AVDictionary*)opts;
@end

typedef BOOL(^IRMovieDecoderInterruptCallback)();

@interface IRMovieDecoder : NSObject {
    pthread_mutex_t video_frame_mutex2;
}

@property (readonly, nonatomic, strong) NSString *path;
@property (readonly, nonatomic) BOOL isEOF;
@property (readwrite,nonatomic) CGFloat position;
@property (readonly, nonatomic) CGFloat duration;
@property (readonly, nonatomic) CGFloat fps;
@property (readonly, nonatomic) CGFloat sampleRate;
@property (readonly, nonatomic) NSUInteger frameWidth;
@property (readonly, nonatomic) NSUInteger frameHeight;
@property (readonly, nonatomic) NSUInteger audioStreamsCount;
@property (readwrite,nonatomic) NSInteger selectedAudioStream;
@property (readonly, nonatomic) NSUInteger subtitleStreamsCount;
@property (readwrite,nonatomic) NSInteger selectedSubtitleStream;
@property (readonly, nonatomic) BOOL validVideo;
@property (readonly, nonatomic) BOOL validAudio;
@property (readonly, nonatomic) BOOL validSubtitles;
@property (readonly, nonatomic, strong) NSDictionary *info;
@property (readonly, nonatomic, strong) NSString *videoStreamFormatName;
@property (readonly, nonatomic) BOOL isNetwork;
@property (readonly, nonatomic) CGFloat startTime;
@property (readwrite, nonatomic) BOOL disableDeinterlacing;
@property (readwrite, nonatomic, strong) IRMovieDecoderInterruptCallback interruptCallback;
@property (nonatomic, weak) id<IRMovieDecoderDelegate> delegate;

+ (id) movieDecoderWithContentPath: (NSString *) path
                             error: (NSError **) perror;

- (BOOL) openFile: (NSString *) path
            error: (NSError **) perror
         duration: (int64_t) contextDuration;

-(void) closeFile;

- (BOOL) setupVideoFrameFormat: (IRFrameFormat) format;

-(void) readFrames;

- (NSArray *) decodeFramesNew: (CGFloat) minDuration;

- (void) freeBuffered;

-(void)receiveMemoryWarning;

-(void)startMaxBufferDuration;

-(void)increaseMaxBufferDuration;

-(void)stopMaxBufferDuration;

-(CGFloat)getBufferDuration;
-(long long)getTotalSize;

@end

@interface IRMovieSubtitleASSParser : NSObject

+ (NSArray *) parseEvents: (NSString *) events;
+ (NSArray *) parseDialogue: (NSString *) dialogue
                  numFields: (NSUInteger) numFields;
+ (NSString *) removeCommandsFromEventText: (NSString *) text;

@end

NS_ASSUME_NONNULL_END
