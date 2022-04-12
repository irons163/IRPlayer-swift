//
//  IRFFPlayer.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

//#import "IRFFPlayer.h"
//@implementation IRFFPlayer
//@end

#import <IRPlayer_swift/IRPlayer_swift-Swift.h>
#import "IRFFPlayer.h"
#import "IRFFDecoder.h"
#import "IRAudioManager.h"
#import "IRPlayerNotification.h"
#import "IRPlayerMacro.h"
#import "IRPlayerImp+DisplayView.h"
#import "IRFFTrack.h"
//#import "IRPlayerImp+Private.h"

@interface IRPlayerImp ()

@property IRAudioManager * manager;

@end

//@interface IRFFPlayer () <IRFFDecoderDelegate, IRFFDecoderAudioOutput, IRAudioManagerDelegate>
@interface IRFFPlayer () <IRFFDecoderDelegate, IRFFDecoderAudioOutput>

@property (nonatomic, strong) NSLock * stateLock;

@property (nonatomic, weak) IRPlayerImp * abstractPlayer;

@property (nonatomic, strong) IRFFDecoder * decoder;
@property (nonatomic, strong) IRAudioManager * audioManager;

@property (nonatomic, assign) BOOL prepareToken;
@property (nonatomic, assign) IRPlayerState state;
@property (nonatomic, assign) NSTimeInterval progress;

@property (nonatomic, assign) NSTimeInterval lastPostProgressTime;
@property (nonatomic, assign) NSTimeInterval lastPostPlayableTime;

@property (nonatomic, assign) BOOL playing;

@property (nonatomic, strong) IRFFAudioFrame * currentAudioFrame;

@end

@implementation IRFFPlayer

+ (instancetype)playerWithAbstractPlayer:(IRPlayerImp *)abstractPlayer
{
    return [[self alloc] initWithAbstractPlayer:abstractPlayer];
}

- (instancetype)initWithAbstractPlayer:(IRPlayerImp *)abstractPlayer
{
    if (self = [super init]) {
        self.abstractPlayer = abstractPlayer;
        self.stateLock = [[NSLock alloc] init];
//        self.audioManager = [IRAudioManager manager];
        self.audioManager = self.abstractPlayer.manager;
        [self.audioManager registerAudioSession];
    }
    return self;
}

- (void)play
{
    self.playing = YES;
    [self.decoder resume];

    switch (self.state) {
        case IRPlayerStateFinished:
            [self seekToTime:0];
            break;
        case IRPlayerStateNone:
        case IRPlayerStateFailed:
        case IRPlayerStateBuffering:
            self.state = IRPlayerStateBuffering;
            break;
        case IRPlayerStateReadyToPlay:
        case IRPlayerStatePlaying:
        case IRPlayerStateSuspend:
            self.state = IRPlayerStatePlaying;
            break;
    }
}

- (void)pause
{
    self.playing = NO;
    [self.decoder pause];

    switch (self.state) {
        case IRPlayerStateNone:
        case IRPlayerStateSuspend:
            break;
        case IRPlayerStateFailed:
        case IRPlayerStateReadyToPlay:
        case IRPlayerStateFinished:
        case IRPlayerStatePlaying:
        case IRPlayerStateBuffering:
        {
            self.state = IRPlayerStateSuspend;
        }
            break;
    }
}

- (void)stop
{
    [self clean];
}

- (void)seekToTime:(NSTimeInterval)time
{
    [self.decoder seekToTime:time];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler
{
    [self.decoder seekToTime:time completeHandler:completeHandler];
}

- (void)setState:(IRPlayerState)state
{
    [self.stateLock lock];
    if (_state != state) {
        IRPlayerState temp = _state;
        _state = state;
        if (_state != IRPlayerStateFailed) {
            self.abstractPlayer.error = nil;
        }
        if (_state == IRPlayerStatePlaying) {
            [self.audioManager playWithDelegate:self];
        } else {
            [self.audioManager pause];
        }
        [IRPlayerNotification postPlayer:self.abstractPlayer statePrevious:temp current:_state];
    }
    [self.stateLock unlock];
}

- (void)setProgress:(NSTimeInterval)progress
{
    if (_progress != progress) {
        _progress = progress;
        NSTimeInterval duration = self.duration;
        if (_progress <= 0.000001 || _progress == duration) {
            [IRPlayerNotification postPlayer:self.abstractPlayer progressPercent:@(_progress/duration) current:@(_progress) total:@(duration)];
        } else {
            NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
            if (currentTime - self.lastPostProgressTime >= 1) {
                self.lastPostProgressTime = currentTime;
                if (!self.decoder.seekEnable) {
                    duration = _progress;
                }
                [IRPlayerNotification postPlayer:self.abstractPlayer progressPercent:@(_progress/duration) current:@(_progress) total:@(duration)];
            }
        }
    }
}

- (void)setPlayableTime:(NSTimeInterval)playableTime
{
    NSTimeInterval duration = self.duration;
    if (playableTime > duration) {
        playableTime = duration;
    } else if (playableTime < 0) {
        playableTime = 0;
    }

    if (_playableTime != playableTime) {
        _playableTime = playableTime;
        if (_playableTime == 0 || _playableTime == duration) {
            [IRPlayerNotification postPlayer:self.abstractPlayer playablePercent:@(_playableTime/self.duration) current:@(_playableTime) total:@(duration)];
        } else if (!self.decoder.endOfFile && self.decoder.seekEnable) {
            NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
            if (currentTime - self.lastPostPlayableTime >= 1) {
                self.lastPostPlayableTime = currentTime;
                [IRPlayerNotification postPlayer:self.abstractPlayer playablePercent:@(_playableTime/duration) current:@(_playableTime) total:@(duration)];
            }
        }
    }
}

- (NSTimeInterval)duration
{
    return self.decoder.duration;
}

- (CGSize)presentationSize
{
    if (self.decoder.prepareToDecode) {
        return self.decoder.presentationSize;
    }
    return CGSizeZero;
}

- (NSTimeInterval)bitrate
{
    if (self.decoder.prepareToDecode) {
        return self.decoder.bitrate;
    }
    return 0;
}

- (void)reloadVolume
{
    self.audioManager.volume = self.abstractPlayer.volume;
}

- (void)reloadPlayableBufferInterval
{
    self.decoder.minBufferedDruation = self.abstractPlayer.playableBufferInterval;
}

#pragma mark - replace video

- (void)replaceVideo
{
    [self clean];
    if (!self.abstractPlayer.contentURL) return;

    self.decoder = [IRFFDecoder decoderWithContentURL:self.abstractPlayer.contentURL delegate:self videoOutput:self.abstractPlayer.displayView audioOutput:self];
    self.decoder.hardwareDecoderEnable = self.abstractPlayer.decoder.ffmpegHardwareDecoderEnable;
    [self.decoder open];
    [self reloadVolume];
    [self reloadPlayableBufferInterval];
    
    if(self.decoder.hardwareDecoderEnable) {
        if(self.abstractPlayer.displayView.pixelFormat != NV12_IRPixelFormat) {
            [self.abstractPlayer.displayView setPixelFormat:NV12_IRPixelFormat];
        }
    } else {
        if(self.abstractPlayer.displayView.pixelFormat != YUV_IRPixelFormat) {
            [self.abstractPlayer.displayView setPixelFormat:YUV_IRPixelFormat];
        }
    }

    switch (self.abstractPlayer.videoType) {
        case IRVideoTypeNormal:
            self.abstractPlayer.displayView.rendererType = IRDisplayRendererTypeFFmpegPexelBuffer;
            break;
        case IRVideoTypeVR:
            self.abstractPlayer.displayView.rendererType = IRDisplayRendererTypeFFmpegPexelBufferVR;
            break;
        case IRVideoTypeFisheye:
        case IRVideoTypePano:
        case IRVideoTypeCustom:
            self.abstractPlayer.displayView.rendererType = IRDisplayRendererTypeFFmpegPexelBuffer;
            break;
    }
}

#pragma mark - IRFFDecoderDelegate

- (void)decoderWillOpenInputStream:(IRFFDecoder *)decoder
{
    self.state = IRPlayerStateBuffering;
}

- (void)decoderDidPrepareToDecodeFrames:(IRFFDecoder *)decoder
{
    self.state = IRPlayerStateReadyToPlay;
}

- (void)decoderDidEndOfFile:(IRFFDecoder *)decoder
{
    self.playableTime = self.duration;
}

- (void)decoderDidPlaybackFinished:(IRFFDecoder *)decoder
{
    self.state = IRPlayerStateFinished;
}

- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfBuffering:(BOOL)buffering
{
    if (buffering) {
        self.state = IRPlayerStateBuffering;
    } else {
        if (self.playing) {
            self.state = IRPlayerStatePlaying;
        } else if (!self.prepareToken) {
            self.state = IRPlayerStateReadyToPlay;
            self.prepareToken = YES;
        } else {
            self.state = IRPlayerStateSuspend;
        }
    }
}

- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfBufferedDuration:(NSTimeInterval)bufferedDuration
{
    self.playableTime = self.progress + bufferedDuration;
}

- (void)decoder:(IRFFDecoder *)decoder didChangeValueOfProgress:(NSTimeInterval)progress
{
    self.progress = progress;
}

- (void)decoder:(IRFFDecoder *)decoder didError:(NSError *)error
{
    [self errorHandler:error];
}

- (void)errorHandler:(NSError *)error
{
    IRError * obj = [[IRError alloc] init];
    obj.error = error;
    self.abstractPlayer.error = obj;
    self.state = IRPlayerStateFailed;
    [IRPlayerNotification postPlayer:self.abstractPlayer error:obj];
}

#pragma mark - clean

- (void)clean
{
    [self cleanDecoder];
    [self cleanFrame];
    [self cleanPlayer];
}

- (void)cleanPlayer
{
    self.playing = NO;
    self.state = IRPlayerStateNone;
    self.progress = 0;
    self.playableTime = 0;
    self.prepareToken = NO;
    self.lastPostProgressTime = 0;
    self.lastPostPlayableTime = 0;
    [self.abstractPlayer.displayView cleanEmptyBuffer];
}

- (void)cleanFrame
{
    [self.currentAudioFrame stopPlaying];
    self.currentAudioFrame = nil;
}

- (void)cleanDecoder
{
    if (self.decoder) {
        [self.decoder closeFile];
        self.decoder = nil;
    }
}

- (void)dealloc
{
    [self clean];
    [self.audioManager unregisterAudioSession];
    IRPlayerLog(@"IRFFPlayer release");
}

#pragma mark - audio

- (Float64)samplingRate
{
    return self.audioManager.samplingRate;
}

- (UInt32)numberOfChannels
{
    return self.audioManager.numberOfChannels;
}

- (void)audioManager:(IRAudioManager *)audioManager outputData:(float *)outputData numberOfFrames:(UInt32)numberOfFrames numberOfChannels:(UInt32)numberOfChannels
{
    if (!self.playing) {
        memset(outputData, 0, numberOfFrames * numberOfChannels * sizeof(float));
        return;
    }
    @autoreleasepool
    {
        while (numberOfFrames > 0)
        {
            if (!self.currentAudioFrame) {
                self.currentAudioFrame = [self.decoder fetchAudioFrame];
                [self.currentAudioFrame startPlaying];
            }
            if (!self.currentAudioFrame) {
                memset(outputData, 0, numberOfFrames * numberOfChannels * sizeof(float));
                return;
            }

            const Byte * bytes = (Byte *)self.currentAudioFrame->samples + self.currentAudioFrame->output_offset;
            const NSUInteger bytesLeft = self.currentAudioFrame->length - self.currentAudioFrame->output_offset;
            const NSUInteger frameSizeOf = numberOfChannels * sizeof(float);
            const NSUInteger bytesToCopy = MIN(numberOfFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;

            memcpy(outputData, bytes, bytesToCopy);
            numberOfFrames -= framesToCopy;
            outputData += framesToCopy * numberOfChannels;

            if (bytesToCopy < bytesLeft) {
                self.currentAudioFrame->output_offset += bytesToCopy;
            } else {
                [self.currentAudioFrame stopPlaying];
                self.currentAudioFrame = nil;
            }
        }
    }
}


#pragma mark - track info

- (BOOL)videoEnable
{
    return self.decoder.videoEnable;
}

- (BOOL)audioEnable
{
    return self.decoder.audioEnable;
}

- (IRPlayerTrack *)videoTrack
{
    return [self playerTrackFromFFTrack:self.decoder.videoTrack];
}

- (IRPlayerTrack *)audioTrack
{
    return [self playerTrackFromFFTrack:self.decoder.audioTrack];
}

- (NSArray <IRPlayerTrack *> *)videoTracks
{
    return [self playerTracksFromFFTracks:self.decoder.videoTracks];
}

- (NSArray <IRPlayerTrack *> *)audioTracks
{
    return [self playerTracksFromFFTracks:self.decoder.audioTracks];;
}

- (void)selectAudioTrackIndex:(int)audioTrackIndex
{
    [self.decoder selectAudioTrackIndex:audioTrackIndex];
}

- (IRPlayerTrack *)playerTrackFromFFTrack:(IRFFTrack *)track
{
    if (track) {
        IRPlayerTrack * obj = [[IRPlayerTrack alloc] init];
        obj.index = track.index;
        obj.name = track.metadata.language;
        return obj;
    }
    return nil;
}

- (NSArray <IRPlayerTrack *> *)playerTracksFromFFTracks:(NSArray <IRFFTrack *> *)tracks
{
    NSMutableArray <IRPlayerTrack *> * array = [NSMutableArray array];
    for (IRFFTrack * obj in tracks) {
        IRPlayerTrack * track = [self playerTrackFromFFTrack:obj];
        [array addObject:track];
    }
    if (array.count > 0) {
        return array;
    }
    return nil;
}

@end
