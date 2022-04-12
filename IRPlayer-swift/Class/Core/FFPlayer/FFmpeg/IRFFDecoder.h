//
//  IRFFDecoder.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "IRFFAudioFrame.h"
#import "IRFFVideoFrame.h"
#import "IRFFTrack.h"

@class IRFFDecoder;

NS_ASSUME_NONNULL_BEGIN

@protocol IRFFDecoderDelegate <NSObject>

@optional

- (void)decoderWillOpenInputStream:(IRFFDecoder *)decoder;      // open input stream
- (void)decoderDidPrepareToDecodeFrames:(IRFFDecoder *)decoder;     // prepare decode frames
- (void)decoderDidEndOfFile:(IRFFDecoder *)decoder;     // end of file
- (void)decoderDidPlaybackFinished:(IRFFDecoder *)decoder;
- (void)decoder:(IRFFDecoder *)decoder didError:(NSError *)error;       // error callback

// value change
- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfBuffering:(BOOL)buffering;
- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfBufferedDuration:(NSTimeInterval)bufferedDuration;
- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfProgress:(NSTimeInterval)progress;

@end

@protocol IRFFDecoderVideoOutput <NSObject>

- (void)decoder:(IRFFDecoder *)decoder renderVideoFrame:(IRFFVideoFrame *)videoFrame;

@end

@protocol IRFFDecoderAudioOutput <NSObject>

- (Float64)samplingRate;
- (UInt32)numberOfChannels;

@end

@interface IRFFDecoder : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)decoderWithContentURL:(NSURL *)contentURL delegate:(id <IRFFDecoderDelegate>)delegate videoOutput:(id <IRFFDecoderVideoOutput>)videoOutput audioOutput:(id <IRFFDecoderAudioOutput>)audioOutput;

@property (nonatomic, strong, readonly) NSError * error;

@property (nonatomic, copy, readonly) NSURL * contentURL;

@property (nonatomic, copy, readonly) NSDictionary * metadata;
@property (nonatomic, assign, readonly) CGSize presentationSize;
@property (nonatomic, assign, readonly) CGFloat aspect;
@property (nonatomic, assign, readonly) NSTimeInterval bitrate;
@property (nonatomic, assign, readonly) NSTimeInterval progress;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval bufferedDuration;

@property (nonatomic, assign) NSTimeInterval minBufferedDruation;
@property (nonatomic, assign) BOOL hardwareDecoderEnable;       // default is YES;

@property (nonatomic, assign, readonly) BOOL buffering;

@property (nonatomic, assign, readonly) BOOL playbackFinished;
@property (atomic, assign, readonly) BOOL closed;
@property (atomic, assign, readonly) BOOL endOfFile;
@property (atomic, assign, readonly) BOOL paused;
@property (atomic, assign, readonly) BOOL seeking;
@property (atomic, assign, readonly) BOOL reading;
@property (atomic, assign, readonly) BOOL prepareToDecode;

- (void)pause;
- (void)resume;
- (IRFFAudioFrame *)fetchAudioFrame;

@property (nonatomic, assign, readonly) BOOL seekEnable;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler;

- (void)open;
- (void)closeFile;      // when release of active calls, or when called in dealloc might block the thread


#pragma mark - track info

@property (nonatomic, assign, readonly) BOOL videoEnable;
@property (nonatomic, assign, readonly) BOOL audioEnable;

@property (nonatomic, strong, readonly) IRFFTrack * videoTrack;
@property (nonatomic, strong, readonly) IRFFTrack * audioTrack;

@property (nonatomic, strong, readonly) NSArray <IRFFTrack *> * videoTracks;
@property (nonatomic, strong, readonly) NSArray <IRFFTrack *> * audioTracks;

- (void)selectAudioTrackIndex:(int)audioTrackIndex;

@end


NS_ASSUME_NONNULL_END
