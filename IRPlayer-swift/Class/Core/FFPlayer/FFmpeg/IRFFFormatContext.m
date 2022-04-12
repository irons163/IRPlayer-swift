//
//  IRFFFormatContext.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFFormatContext.h"
#import "IRFFTools.h"

static int ffmpeg_interrupt_callback(void *ctx)
{
    IRFFFormatContext * obj = (__bridge IRFFFormatContext *)ctx;
    return [obj.delegate formatContextNeedInterrupt:obj];
}

@interface IRFFFormatContext ()

@property (nonatomic, copy) NSURL * contentURL;

@property (nonatomic, copy) NSError * error;
@property (nonatomic, copy) NSDictionary * metadata;

@property (nonatomic, assign) BOOL videoEnable;
@property (nonatomic, assign) BOOL audioEnable;

@property (nonatomic, strong) IRFFTrack * videoTrack;
@property (nonatomic, strong) IRFFTrack * audioTrack;

@property (nonatomic, strong) NSArray <IRFFTrack *> * videoTracks;
@property (nonatomic, strong) NSArray <IRFFTrack *> * audioTracks;

@property (nonatomic, assign) NSTimeInterval videoTimebase;
@property (nonatomic, assign) NSTimeInterval videoFPS;
@property (nonatomic, assign) CGSize videoPresentationSize;
@property (nonatomic, assign) CGFloat videoAspect;

@property (nonatomic, assign) NSTimeInterval audioTimebase;

@end

@implementation IRFFFormatContext

+ (instancetype)formatContextWithContentURL:(NSURL *)contentURL delegate:(id<IRFFFormatContextDelegate>)delegate
{
    return [[self alloc] initWithContentURL:contentURL delegate:delegate];
}

- (instancetype)initWithContentURL:(NSURL *)contentURL delegate:(id<IRFFFormatContextDelegate>)delegate
{
    if (self = [super init])
    {
        self.contentURL = contentURL;
        self.delegate = delegate;
    }
    return self;
}

- (void)setupSync
{
    self.error = [self openStream];
    if (self.error)
    {
        return;
    }
    
    [self openTracks];
    NSError * videoError = [self openVideoTrack];
    NSError * audioError = [self openAutioTrack];
    
    if (videoError && audioError)
    {
        if (videoError.code == IRFFDecoderErrorCodeStreamNotFound && audioError.code != IRFFDecoderErrorCodeStreamNotFound)
        {
            self.error = audioError;
        }
        else
        {
            self.error = videoError;
        }
        return;
    }
}

- (NSError *)openStream
{
    int reslut = 0;
    NSError * error = nil;
    
    self->_format_context = avformat_alloc_context();
    if (!_format_context)
    {
        reslut = -1;
        error = [NSError errorWithDomain:@"IRFFDecoderErrorCodeFormatCreate error" code:IRFFDecoderErrorCodeFormatCreate userInfo:nil];
        return error;
    }
    
    _format_context->interrupt_callback.callback = ffmpeg_interrupt_callback;
    _format_context->interrupt_callback.opaque = (__bridge void *)self;
    
    reslut = avformat_open_input(&_format_context, [self contentURLString].UTF8String, NULL, NULL);
    error = IRFFCheckErrorCode(reslut, IRFFDecoderErrorCodeFormatOpenInput);
    if (error || !_format_context)
    {
        if (_format_context)
        {
            avformat_free_context(_format_context);
        }
        return error;
    }
    
    reslut = avformat_find_stream_info(_format_context, NULL);
    error = IRFFCheckErrorCode(reslut, IRFFDecoderErrorCodeFormatFindStreamInfo);
    if (error || !_format_context)
    {
        if (_format_context)
        {
            avformat_close_input(&_format_context);
        }
        return error;
    }
    self.metadata = IRFFFoundationBrigeOfAVDictionary(_format_context->metadata);
    
    return error;
}

- (void)openTracks
{
    NSMutableArray <IRFFTrack *> * videoTracks = [NSMutableArray array];
    NSMutableArray <IRFFTrack *> * audioTracks = [NSMutableArray array];

    for (int i = 0; i < _format_context->nb_streams; i++)
    {
        AVStream * stream = _format_context->streams[i];
        switch (stream->codecpar->codec_type)
        {
            case AVMEDIA_TYPE_VIDEO:
            {
                IRFFTrack * track = [[IRFFTrack alloc] init];
                track.type = IRFFTrackTypeVideo;
                track.index = i;
                [videoTracks addObject:track];
            }
                break;
            case AVMEDIA_TYPE_AUDIO:
            {
                IRFFTrack * track = [[IRFFTrack alloc] init];
                track.type = IRFFTrackTypeAudio;
                track.index = i;
                [audioTracks addObject:track];
            }
                break;
            default:
                break;
        }
    }

    if (videoTracks.count > 0)
    {
        self.videoTracks = videoTracks;
    }
    if (audioTracks.count > 0)
    {
        self.audioTracks = audioTracks;
    }
}

- (NSError *)openVideoTrack
{
    NSError * error = nil;
    
    if (self.videoTracks.count > 0)
    {
        for (IRFFTrack * obj in self.videoTracks)
        {
            int index = obj.index;
            if ((_format_context->streams[index]->disposition & AV_DISPOSITION_ATTACHED_PIC) == 0)
            {
                AVCodecContext * codec_context;
                error = [self openStreamWithTrackIndex:index codecContext:&codec_context domain:@"video"];
                if (!error)
                {
                    self.videoTrack = obj;
                    self.videoEnable = YES;
                    self.videoTimebase = IRFFStreamGetTimebase(_format_context->streams[index], 0.00004);
                    self.videoFPS = IRFFStreamGetFPS(_format_context->streams[index], self.videoTimebase);
                    self.videoPresentationSize = CGSizeMake(codec_context->width, codec_context->height);
                    self.videoAspect = (CGFloat)codec_context->width / (CGFloat)codec_context->height;
                    self->_video_codec_context = codec_context;
                    break;
                }
            }
        }
    }
    else
    {
        error = [NSError errorWithDomain:@"video stream not found" code:IRFFDecoderErrorCodeStreamNotFound userInfo:nil];
        return error;
    }
    
    return error;
}

- (NSError *)openAutioTrack
{
    NSError * error = nil;
    
    if (self.audioTracks.count > 0)
    {
        for (IRFFTrack * obj in self.audioTracks)
        {
            int index = obj.index;
            AVCodecContext * codec_context;
            error = [self openStreamWithTrackIndex:index codecContext:&codec_context domain:@"audio"];
            if (!error)
            {
                self.audioTrack = obj;
                self.audioEnable = YES;
                self.audioTimebase = IRFFStreamGetTimebase(_format_context->streams[index], 0.000025);
                self->_audio_codec_context = codec_context;
                break;
            }
        }
    }
    else
    {
        error = [NSError errorWithDomain:@"audio stream not found" code:IRFFDecoderErrorCodeStreamNotFound userInfo:nil];
        return error;
    }
    
    return error;
}

- (NSError *)openStreamWithTrackIndex:(int)trackIndex codecContext:(AVCodecContext **)codecContext domain:(NSString *)domain
{
    int result = 0;
    NSError * error = nil;
    
    AVStream * stream = _format_context->streams[trackIndex];
    AVCodecContext * codec_context = avcodec_alloc_context3(NULL);
    if (!codec_context)
    {
        error = [NSError errorWithDomain:[NSString stringWithFormat:@"%@ codec context create error", domain]
                                    code:IRFFDecoderErrorCodeCodecContextCreate
                                userInfo:nil];
        return error;
    }
    
    result = avcodec_parameters_to_context(codec_context, stream->codecpar);
    error = IRFFCheckErrorCode(result, IRFFDecoderErrorCodeCodecContextSetParam);
    if (error)
    {
        avcodec_free_context(&codec_context);
        return error;
    }
    av_codec_set_pkt_timebase(codec_context, stream->time_base);
    
    AVCodec * codec = avcodec_find_decoder(codec_context->codec_id);
    if (!codec)
    {
        avcodec_free_context(&codec_context);
        error = [NSError errorWithDomain:[NSString stringWithFormat:@"%@ codec not found decoder", domain]
                                    code:IRFFDecoderErrorCodeCodecFindDecoder
                                userInfo:nil];
        return error;
    }
    codec_context->codec_id = codec->id;
    
    result = avcodec_open2(codec_context, codec, NULL);
    error = IRFFCheckErrorCode(result, IRFFDecoderErrorCodeCodecOpen2);
    if (error)
    {
        avcodec_free_context(&codec_context);
        return error;
    }
    
    * codecContext = codec_context;
    return error;
}

- (void)seekFileWithFFTimebase:(NSTimeInterval)time
{
    int64_t ts = time * AV_TIME_BASE;
    av_seek_frame(self->_format_context, -1, ts, AVSEEK_FLAG_BACKWARD);
}

- (void)seekFileWithVideo:(NSTimeInterval)time
{
    if (self.videoEnable)
    {
        int64_t ts = time * 1000.0 / self.videoTimebase;
        av_seek_frame(self->_format_context, -1, ts, AVSEEK_FLAG_BACKWARD);
    }
    else
    {
        [self seekFileWithFFTimebase:time];
    }
}

- (void)seekFileWithAudio:(NSTimeInterval)time
{
    if (self.audioTimebase)
    {
        int64_t ts = time * 1000 / self.audioTimebase;
        av_seek_frame(self->_format_context, -1, ts, AVSEEK_FLAG_BACKWARD);
    }
    else
    {
        [self seekFileWithFFTimebase:time];
    }
}

- (int)readFrame:(AVPacket *)packet
{
    return av_read_frame(self->_format_context, packet);
}

- (BOOL)containAudioTrack:(int)audioTrackIndex
{
    for (IRFFTrack * obj in self.audioTracks) {
        if (obj.index == audioTrackIndex) {
            return YES;
        }
    }
    return NO;
}

- (NSError * )selectAudioTrackIndex:(int)audioTrackIndex
{
    if (audioTrackIndex == self.audioTrack.index) return nil;
    if (![self containAudioTrack:audioTrackIndex]) return nil;
    
    AVCodecContext * codec_context;
    NSError * error = [self openStreamWithTrackIndex:audioTrackIndex codecContext:&codec_context domain:@"audio select"];
    if (!error)
    {
        if (_audio_codec_context)
        {
            avcodec_close(_audio_codec_context);
            _audio_codec_context = NULL;
        }
        for (IRFFTrack * obj in self.audioTracks)
        {
            if (obj.index == audioTrackIndex)
            {
                self.audioTrack = obj;
            }
        }
        self.audioEnable = YES;
        self.audioTimebase = IRFFStreamGetTimebase(_format_context->streams[audioTrackIndex], 0.000025);
        self->_audio_codec_context = codec_context;
    }
    else
    {
        IRPlayerLog(@"select audio track error : %@", error);
    }
    return error;
}

- (NSTimeInterval)duration
{
    if (!self->_format_context) return 0;
    if (self->_format_context->duration == AV_NOPTS_VALUE) return MAXFLOAT;
    return (CGFloat)(self->_format_context->duration) / AV_TIME_BASE;
}

- (NSTimeInterval)bitrate
{
    if (!self->_format_context) return 0;
    return (self->_format_context->bit_rate / 1000.0f);
}

- (NSString *)contentURLString
{
    if ([self.contentURL isFileURL])
    {
        return [self.contentURL path];
    }
    else
    {
        return [self.contentURL absoluteString];
    }
}

- (void)destroyAudioTrack
{
    self.audioEnable = NO;
    self.audioTrack = nil;
    self.audioTracks = nil;
    
    if (_audio_codec_context)
    {
        avcodec_close(_audio_codec_context);
        _audio_codec_context = NULL;
    }
}

- (void)destroyVideoTrack
{
    self.videoEnable = NO;
    self.videoTrack = nil;
    self.videoTracks = nil;
    
    if (_video_codec_context)
    {
        avcodec_close(_video_codec_context);
        _video_codec_context = NULL;
    }
}

- (void)destroy
{
    [self destroyVideoTrack];
    [self destroyAudioTrack];
    if (_format_context)
    {
        avformat_close_input(&_format_context);
        _format_context = NULL;
    }
}

- (void)dealloc
{
    [self destroy];
    IRPlayerLog(@"IRFFFormatContext release");
}

@end
