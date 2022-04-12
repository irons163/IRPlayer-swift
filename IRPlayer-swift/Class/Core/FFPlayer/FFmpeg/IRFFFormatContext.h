//
//  IRFFFormatContext.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "IRFFMetadata.h"
#import "IRFFTrack.h"

NS_ASSUME_NONNULL_BEGIN

@class IRFFFormatContext;

@protocol IRFFFormatContextDelegate <NSObject>

- (BOOL)formatContextNeedInterrupt:(IRFFFormatContext *)formatContext;

@end

@interface IRFFFormatContext : NSObject

{
@public
    AVFormatContext * _format_context;
    AVCodecContext * _video_codec_context;
    AVCodecContext * _audio_codec_context;
}

+ (instancetype)formatContextWithContentURL:(NSURL *)contentURL delegate:(id <IRFFFormatContextDelegate>)delegate;

@property (nonatomic, weak) id <IRFFFormatContextDelegate> delegate;

@property (nonatomic, copy, readonly) NSError * error;

@property (nonatomic, copy, readonly) NSDictionary * metadata;
@property (nonatomic, assign, readonly) NSTimeInterval bitrate;
@property (nonatomic, assign, readonly) NSTimeInterval duration;

@property (nonatomic, assign, readonly) BOOL videoEnable;
@property (nonatomic, assign, readonly) BOOL audioEnable;

@property (nonatomic, strong, readonly) IRFFTrack * videoTrack;
@property (nonatomic, strong, readonly) IRFFTrack * audioTrack;

@property (nonatomic, strong, readonly) NSArray <IRFFTrack *> * videoTracks;
@property (nonatomic, strong, readonly) NSArray <IRFFTrack *> * audioTracks;

@property (nonatomic, assign, readonly) NSTimeInterval videoTimebase;
@property (nonatomic, assign, readonly) NSTimeInterval videoFPS;
@property (nonatomic, assign, readonly) CGSize videoPresentationSize;
@property (nonatomic, assign, readonly) CGFloat videoAspect;

@property (nonatomic, assign, readonly) NSTimeInterval audioTimebase;

- (void)setupSync;
- (void)destroy;

- (void)seekFileWithFFTimebase:(NSTimeInterval)time;
- (int)readFrame:(AVPacket *)packet;

- (BOOL)containAudioTrack:(int)audioTrackIndex;
- (NSError *)selectAudioTrackIndex:(int)audioTrackIndex;

@end


NS_ASSUME_NONNULL_END
