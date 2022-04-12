//
//  IRFFVideoDecoder.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFVideoDecoder.h"
#import "IRFFAVYUVVideoFrame.h"
#import "IRFFCVYUVVideoFrame.h"
#import "IRFFPacketQueue.h"
#import "IRFFFrameQueue.h"
#import "IRFFFramePool.h"
#import "IRFFTools.h"

#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
#import "IRFFVideoToolBox.h"
#endif

static AVPacket flush_packet;

@interface IRFFVideoDecoder ()

{
    AVCodecContext * _codec_context;
    AVFrame * _temp_frame;
}

@property (nonatomic, assign) BOOL decoding;
@property (nonatomic, strong) NSError * error;

@property (nonatomic, assign) BOOL canceled;

@property (nonatomic, strong) IRFFPacketQueue * packetQueue;
@property (nonatomic, strong) IRFFFrameQueue * frameQueue;

@property (nonatomic, strong) IRFFFramePool * framePool;

#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
@property (nonatomic, strong) IRFFVideoToolBox * videoToolBox;
#endif

@end

@implementation IRFFVideoDecoder

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codec_context
                               timebase:(NSTimeInterval)timebase
                                    fps:(NSTimeInterval)fps
                               delegate:(id<IRFFVideoDecoderDlegate>)delegate
{
    return [[self alloc] initWithCodecContext:codec_context
                                     timebase:timebase
                                          fps:fps
                                     delegate:delegate];
}

- (instancetype)initWithCodecContext:(AVCodecContext *)codec_context
                            timebase:(NSTimeInterval)timebase
                                 fps:(NSTimeInterval)fps
                            delegate:(id<IRFFVideoDecoderDlegate>)delegate
{
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            av_init_packet(&flush_packet);
            flush_packet.data = (uint8_t *)&flush_packet;
            flush_packet.duration = 0;
        });
        self.delegate = delegate;
        self->_codec_context = codec_context;
        self->_temp_frame = av_frame_alloc();
        self.timebase = timebase;
        self.fps = fps;
        self.packetQueue = [IRFFPacketQueue packetQueueWithTimebase:timebase];
        self.frameQueue = [IRFFFrameQueue frameQueue];
        self.maxDecodeDuration = 2.f;
#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
        self.videoToolBoxEnable = YES;
#endif
    }
    return self;
}

- (int)packetSize
{
    return self.packetQueue.size;
}

- (BOOL)empty
{
    return [self packetEmpty] && [self frameEmpty];
}

- (BOOL)packetEmpty
{
    return self.packetQueue.count <= 0;
}

- (BOOL)frameEmpty
{
    return self.frameQueue.count <= 0;
}

- (NSTimeInterval)duration
{
    return [self packetDuration] + [self frameDuration];
}

- (NSTimeInterval)packetDuration
{
    return self.packetQueue.duration;
}

- (NSTimeInterval)frameDuration
{
    return self.frameQueue.duration;
}

- (IRFFVideoFrame *)getFrameSync
{
    return [self.frameQueue getFrameSync];
}

- (IRFFVideoFrame *)getFrameAsync
{
    return [self.frameQueue getFrameAsync];
}

- (void)putPacket:(AVPacket)packet
{
    NSTimeInterval duration = 0;
    if (packet.duration <= 0 && packet.size > 0 && packet.data != flush_packet.data) {
        duration = 1.0 / self.fps;
    }
    [self.packetQueue putPacket:packet duration:duration];
}

- (void)flush
{
    [self.packetQueue flush];
    [self.frameQueue flush];
    if (self->_framePool) {
        [self.framePool flush];
    }
    [self putPacket:flush_packet];
}

- (void)destroy
{
    self.canceled = YES;
    
    [self.frameQueue destroy];
    [self.packetQueue destroy];
    if (self->_framePool) {
        [self.framePool flush];
    }
}

static NSTimeInterval max_video_frame_sleep_full_time_interval = 0.1;
static NSTimeInterval max_video_frame_sleep_full_and_pause_time_interval = 0.5;

- (void)decodeFrameThread
{
    self.decoding = YES;
    BOOL finished = NO;
    while (!finished) {
        if (self.canceled || self.error) {
            IRFFThreadLog(@"decode video thread quit");
            break;
        }
        if (self.paused) {
            [NSThread sleepForTimeInterval:0.01];
            continue;
        }
        if (self.endOfFile && self.packetEmpty) {
            IRFFThreadLog(@"decode video finished");
            break;
        }
        if (self.frameDuration >= self.maxDecodeDuration) {
            NSTimeInterval interval = 0;
            if (self.paused) {
                interval = max_video_frame_sleep_full_and_pause_time_interval;
            } else {
                interval = max_video_frame_sleep_full_time_interval;
            }
            IRFFSleepLog(@"decode video thread sleep : %f", interval);
            [NSThread sleepForTimeInterval:interval];
            continue;
        }

        AVPacket packet = [self.packetQueue getPacket];
        if (self.endOfFile) {
            [self.delegate videoDecoderNeedUpdateBufferedDuration:self];
        }
        if (packet.data == flush_packet.data) {
            IRFFDecodeLog(@"video codec flush");
            avcodec_flush_buffers(_codec_context);
#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
            [self.videoToolBox flush];
#endif
            continue;
        }
        if (packet.stream_index < 0 || packet.data == NULL) continue;

        IRFFVideoFrame * videoFrame = nil;
#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
        BOOL vtbEnable = NO;
        if (self.videoToolBoxEnable && _codec_context->codec_id == AV_CODEC_ID_H264) {
            vtbEnable = [self.videoToolBox trySetupVTSession];
        }
        if (vtbEnable) {
            BOOL result = [self.videoToolBox sendPacket:packet];
            if (result) {
                videoFrame = [self videoFrameFromVideoToolBox:packet];
            }
        } else {
#endif
            int result = avcodec_send_packet(_codec_context, &packet);
            if (result < 0 && result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                self.error = IRFFCheckError(result);
                [self delegateErrorCallback];
                goto end;
            }
            while (result >= 0) {
                result = avcodec_receive_frame(_codec_context, _temp_frame);
                if (result < 0) {
                    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
                        break;
                    } else {
                        self.error = IRFFCheckError(result);
                        goto end;
                    }
                }
                videoFrame = [self videoFrameFromTempFrame];
            }
#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
        }
#endif
        if (videoFrame) {
            [self.frameQueue putSortFrame:videoFrame];
        }

    end:
        av_packet_unref(&packet);
    }
    self.decoding = NO;
    [self.delegate videoDecoderNeedCheckBufferingStatus:self];
}

- (IRFFAVYUVVideoFrame *)videoFrameFromTempFrame
{
    if (!_temp_frame->data[0] || !_temp_frame->data[1] || !_temp_frame->data[2]) return nil;
    
    IRFFAVYUVVideoFrame * videoFrame = [self.framePool getUnuseFrame];
    
    [videoFrame setFrameData:_temp_frame width:_codec_context->width height:_codec_context->height];
    videoFrame.position = av_frame_get_best_effort_timestamp(_temp_frame) * self.timebase;
    
    const int64_t frame_duration = av_frame_get_pkt_duration(_temp_frame);
    if (frame_duration) {
        videoFrame.duration = frame_duration * self.timebase;
        videoFrame.duration += _temp_frame->repeat_pict * self.timebase * 0.5;
    } else {
        videoFrame.duration = 1.0 / self.fps;
    }
    return videoFrame;
}

- (IRFFFramePool *)framePool
{
    if (!_framePool) {
        _framePool = [IRFFFramePool videoPool];
    }
    return _framePool;
}

#if IRPLATFORM_TARGET_OS_MAC_OR_IPHONE
- (IRFFVideoFrame *)videoFrameFromVideoToolBox:(AVPacket)packet
{
    CVImageBufferRef imageBuffer = [self.videoToolBox imageBuffer];
    if (imageBuffer == NULL) return nil;
    
    IRFFCVYUVVideoFrame * videoFrame = [[IRFFCVYUVVideoFrame alloc] initWithAVPixelBuffer:imageBuffer];
    
    if (packet.pts != AV_NOPTS_VALUE) {
        videoFrame.position = packet.pts * self.timebase;
    } else {
        videoFrame.position = packet.dts;
    }
    
    const int64_t frame_duration = packet.duration;
    if (frame_duration) {
        videoFrame.duration = frame_duration * self.timebase;
    } else {
        videoFrame.duration = 1.0 / self.fps;
    }
    return videoFrame;
}

- (IRFFVideoToolBox *)videoToolBox
{
    if (!_videoToolBox) {
        _videoToolBox = [IRFFVideoToolBox videoToolBoxWithCodecContext:self->_codec_context];
    }
    return _videoToolBox;
}
#endif

- (void)delegateErrorCallback
{
    if (self.error) {
        [self.delegate videoDecoder:self didError:self.error];
    }
}

- (void)dealloc
{
    if (_temp_frame) {
        av_free(_temp_frame);
        _temp_frame = NULL;
    }
    IRPlayerLog(@"IRFFVideoDecoder release");
}

@end
