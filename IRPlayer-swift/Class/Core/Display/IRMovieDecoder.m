//
//  IRMovieDecoder.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRMovieDecoder.h"
#import <Accelerate/Accelerate.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"
#import "IRFFAVYUVVideoFrame.h"
#import "IRAudioManager.h"
#import "signal.h"
#include <pthread.h>

//#define CONFIG_FRAME_THREAD_ENCODER 0

static pthread_mutex_t video_frame_mutex = PTHREAD_MUTEX_INITIALIZER;
//static pthread_mutex_t video_frame_mutex2 = PTHREAD_MUTEX_INITIALIZER;

////////////////////////////////////////////////////////////////////////////////
NSString * IRMovieErrorDomain = @"ru.kolyvan.irmovie";
static void FFLog(void* context, int level, const char* format, va_list args);

static NSError * irmovieError (NSInteger code, id info)
{
    NSDictionary *userInfo = nil;
    
    if ([info isKindOfClass: [NSDictionary class]]) {
        
        userInfo = info;
        
    } else if ([info isKindOfClass: [NSString class]]) {
        
        userInfo = @{ NSLocalizedDescriptionKey : info };
    }
    
    return [NSError errorWithDomain:IRMovieErrorDomain
                               code:code
                           userInfo:userInfo];
}

static NSString * errorMessage (IRMovieError errorCode)
{
    switch (errorCode) {
        case IRMovieErrorNone:
            return @"";
            
        case IRMovieErrorOpenFile:
            return NSLocalizedString(@"Unable to open file", nil);
            
        case IRMovieErrorStreamInfoNotFound:
            return NSLocalizedString(@"Unable to find stream information", nil);
            
        case IRMovieErrorStreamNotFound:
            return NSLocalizedString(@"Unable to find stream", nil);
            
        case IRMovieErrorCodecNotFound:
            return NSLocalizedString(@"Unable to find codec", nil);
            
        case IRMovieErrorOpenCodec:
            return NSLocalizedString(@"Unable to open codec", nil);
            
        case IRMovieErrorAllocateFrame:
            return NSLocalizedString(@"Unable to allocate frame", nil);
            
        case IRMovieErroSetupScaler:
            return NSLocalizedString(@"Unable to setup scaler", nil);
            
        case IRMovieErroReSampler:
            return NSLocalizedString(@"Unable to setup resampler", nil);
            
        case IRMovieErroUnsupported:
            return NSLocalizedString(@"The ability is not supported", nil);
    }
}

////////////////////////////////////////////////////////////////////////////////

static BOOL audioCodecIsSupported(AVCodecContext *audio)
{
//    if (audio->sample_fmt == AV_SAMPLE_FMT_S16) {
//
//        id<IRAudioManager> audioManager = [IRAudioManager audioManager];
//        return  (int)audioManager.samplingRate == audio->sample_rate &&
//        audioManager.numOutputChannels == audio->channels;
//    }
    return NO;
}

#ifdef DEBUG
static void fillSignal(SInt16 *outData,  UInt32 numFrames, UInt32 numChannels)
{
    static float phase = 0.0;
    
    for (int i=0; i < numFrames; ++i)
    {
        for (int iChannel = 0; iChannel < numChannels; ++iChannel)
        {
            float theta = phase * M_PI * 2;
            outData[i*numChannels + iChannel] = sin(theta) * (float)INT16_MAX;
        }
        phase += 1.0 / (44100 / 440.0);
        if (phase > 1.0) phase = -1;
    }
}

static void fillSignalF(float *outData,  UInt32 numFrames, UInt32 numChannels)
{
    static float phase = 0.0;
    
    for (int i=0; i < numFrames; ++i)
    {
        for (int iChannel = 0; iChannel < numChannels; ++iChannel)
        {
            float theta = phase * M_PI * 2;
            outData[i*numChannels + iChannel] = sin(theta);
        }
        phase += 1.0 / (44100 / 440.0);
        if (phase > 1.0) phase = -1;
    }
}

static void testConvertYUV420pToRGB(AVFrame * frame, uint8_t *outbuf, int linesize, int height)
{
    const int linesizeY = frame->linesize[0];
    const int linesizeU = frame->linesize[1];
    const int linesizeV = frame->linesize[2];
    
    assert(height == frame->height);
    assert(linesize  <= linesizeY * 3);
    assert(linesizeY == linesizeU * 2);
    assert(linesizeY == linesizeV * 2);
    
    uint8_t *pY = frame->data[0];
    uint8_t *pU = frame->data[1];
    uint8_t *pV = frame->data[2];
    
    const int width = linesize / 3;
    
    for (int y = 0; y < height; y += 2) {
        
        uint8_t *dst1 = outbuf + y       * linesize;
        uint8_t *dst2 = outbuf + (y + 1) * linesize;
        
        uint8_t *py1  = pY  +  y       * linesizeY;
        uint8_t *py2  = py1 +            linesizeY;
        uint8_t *pu   = pU  + (y >> 1) * linesizeU;
        uint8_t *pv   = pV  + (y >> 1) * linesizeV;
        
        for (int i = 0; i < width; i += 2) {
            
            int Y1 = py1[i];
            int Y2 = py2[i];
            int Y3 = py1[i+1];
            int Y4 = py2[i+1];
            
            int U = pu[(i >> 1)] - 128;
            int V = pv[(i >> 1)] - 128;
            
            int dr = (int)(             1.402f * V);
            int dg = (int)(0.344f * U + 0.714f * V);
            int db = (int)(1.772f * U);
            
            int r1 = Y1 + dr;
            int g1 = Y1 - dg;
            int b1 = Y1 + db;
            
            int r2 = Y2 + dr;
            int g2 = Y2 - dg;
            int b2 = Y2 + db;
            
            int r3 = Y3 + dr;
            int g3 = Y3 - dg;
            int b3 = Y3 + db;
            
            int r4 = Y4 + dr;
            int g4 = Y4 - dg;
            int b4 = Y4 + db;
            
            r1 = r1 > 255 ? 255 : r1 < 0 ? 0 : r1;
            g1 = g1 > 255 ? 255 : g1 < 0 ? 0 : g1;
            b1 = b1 > 255 ? 255 : b1 < 0 ? 0 : b1;
            
            r2 = r2 > 255 ? 255 : r2 < 0 ? 0 : r2;
            g2 = g2 > 255 ? 255 : g2 < 0 ? 0 : g2;
            b2 = b2 > 255 ? 255 : b2 < 0 ? 0 : b2;
            
            r3 = r3 > 255 ? 255 : r3 < 0 ? 0 : r3;
            g3 = g3 > 255 ? 255 : g3 < 0 ? 0 : g3;
            b3 = b3 > 255 ? 255 : b3 < 0 ? 0 : b3;
            
            r4 = r4 > 255 ? 255 : r4 < 0 ? 0 : r4;
            g4 = g4 > 255 ? 255 : g4 < 0 ? 0 : g4;
            b4 = b4 > 255 ? 255 : b4 < 0 ? 0 : b4;
            
            dst1[3*i + 0] = r1;
            dst1[3*i + 1] = g1;
            dst1[3*i + 2] = b1;
            
            dst2[3*i + 0] = r2;
            dst2[3*i + 1] = g2;
            dst2[3*i + 2] = b2;
            
            dst1[3*i + 3] = r3;
            dst1[3*i + 4] = g3;
            dst1[3*i + 5] = b3;
            
            dst2[3*i + 3] = r4;
            dst2[3*i + 4] = g4;
            dst2[3*i + 5] = b4;
        }
    }
}
#endif

static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase)
{
    CGFloat fps;
    CGFloat timebase;
    
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    else
        timebase = defaultTimeBase;
    
    if (st->codec->ticks_per_frame != 1) {
        NSLog(@"WARNING: st.codec.ticks_per_frame=%d", st->codec->ticks_per_frame);
        //timebase *= st->codec->ticks_per_frame;
    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}

static NSArray *collectStreams(AVFormatContext *formatCtx, enum AVMediaType codecType)
{
    NSMutableArray *ma = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; ++i)
        if (codecType == formatCtx->streams[i]->codec->codec_type)
            [ma addObject: [NSNumber numberWithInteger: i]];
    return [ma copy];
}

static NSData * copyFrameData(UInt8 *src, int linesize, int width, int height)
{
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength: width * height];
    Byte *dst = md.mutableBytes;
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    return md;
}

static BOOL isNetworkPath (NSString *path)
{
    NSRange r = [path rangeOfString:@":"];
    if (r.location == NSNotFound)
        return NO;
    NSString *scheme = [path substringToIndex:r.length];
    if ([scheme isEqualToString:@"file"])
        return NO;
    return YES;
}

static int interrupt_callback(void *ctx);

@interface IRVideoFrameRGB ()
@property (readwrite, nonatomic) NSUInteger linesize;
@property (readwrite, nonatomic, strong) NSData *rgb;
@end

@implementation IRVideoFrameRGB
- (IRFrameFormat) format { return IRFrameFormatRGB; }
- (UIImage *) asImage
{
    UIImage *image = nil;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_rgb));
    if (provider) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (colorSpace) {
            CGImageRef imageRef = CGImageCreate(self.width,
                                                self.height,
                                                8,
                                                24,
                                                self.linesize,
                                                colorSpace,
                                                kCGBitmapByteOrderDefault,
                                                provider,
                                                NULL,
                                                YES, // NO
                                                kCGRenderingIntentDefault);
            
            if (imageRef) {
                image = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CGDataProviderRelease(provider);
    }
    
    return image;
}
@end

@interface IRFFAVYUVVideoFrame()
//@property (nonatomic, strong) NSData *luma;
//@property (nonatomic, strong) NSData *chromaB;
//@property (nonatomic, strong) NSData *chromaR;
@end

@interface IRMovieDecoder () {
    
    AVFormatContext     *_formatCtx;
    AVCodecContext      *_videoCodecCtx;
    AVCodecContext      *_audioCodecCtx;
    AVCodecContext      *_subtitleCodecCtx;
    AVFrame             *_videoFrame;
    AVFrame             *_audioFrame;
    NSInteger           _videoStream;
    NSInteger           _audioStream;
    NSInteger           _subtitleStream;
    AVPicture           _picture;
    BOOL                _pictureValid;
    struct SwsContext   *_swsContext;
    CGFloat             _videoTimeBase;
    CGFloat             _audioTimeBase;
    CGFloat             _position;
    NSArray             *_videoStreams;
    NSArray             *_audioStreams;
    NSArray             *_subtitleStreams;
    SwrContext          *_swrContext;
    void                *_swrBuffer;
    NSUInteger          _swrBufferSize;
    NSDictionary        *_info;
    IRFrameFormat       _videoFrameFormat;
    NSUInteger          _artworkStream;
    NSInteger           _subtitleASSEvents;
    
    BOOL finished;
    BOOL readFrameFinished;
    BOOL closeReadFrame;
    dispatch_queue_t    _dispatchQueue;
    NSObject*           _framelock;
    
    float maxBufferDurationForMemoryLeak;
    float maxBufferDuration;
    float minBufferDuration;
    CGFloat bufferDuration;
    NSMutableArray *bufferArray;
    //AVPacket bufferArray[100];
    CGFloat durationTotal;
    BOOL justOnce;
    long long totalSize;
}
@end

@implementation IRMovieDecoder

@dynamic duration;
@dynamic position;
@dynamic frameWidth;
@dynamic frameHeight;
@dynamic sampleRate;
@dynamic audioStreamsCount;
@dynamic subtitleStreamsCount;
@dynamic selectedAudioStream;
@dynamic selectedSubtitleStream;
@dynamic validAudio;
@dynamic validVideo;
@dynamic validSubtitles;
@dynamic info;
@dynamic videoStreamFormatName;
@dynamic startTime;



- (CGFloat) duration
{
    if (!_formatCtx)
        return 0;
    if (_formatCtx->duration == AV_NOPTS_VALUE)
        return MAXFLOAT;
    return (CGFloat)_formatCtx->duration / AV_TIME_BASE;
}

- (CGFloat) position
{
    return _position;
}

- (void) setPosition: (CGFloat)seconds
{
    //    pthread_mutex_lock(&video_frame_mutex2);
    //    NSLog(@"pthread_mutex_lock video_frame_mutex2 setPosition");
    @synchronized(_framelock) {
        NSLog(@"avformat_seek_file seek");
        totalSize = -1;
        _position = seconds;
        _isEOF = NO;
        
        if (_videoStream != -1) {
            //        avcodec_flush_buffers(_videoCodecCtx);
            int64_t ts = (int64_t)(seconds / _videoTimeBase);
            int error_code = avformat_seek_file(_formatCtx, _videoStream, 0, ts, ts, AVSEEK_FLAG_FRAME);
            avcodec_flush_buffers(_videoCodecCtx);
            NSLog(@"avformat_seek_file _videoStream:%d",error_code);
        }
        
        else if (_audioStream != -1) {
            //        avcodec_flush_buffers(_videoCodecCtx);
            int64_t ts = (int64_t)(seconds / _audioTimeBase);
            int error_code = avformat_seek_file(_formatCtx, _audioStream, 0, ts, ts, AVSEEK_FLAG_FRAME);
            avcodec_flush_buffers(_audioCodecCtx);
            NSLog(@"avformat_seek_file _audioStream:%d",error_code);
        }
    }
    //    NSLog(@"pthread_mutex_unlock video_frame_mutex2 setPosition");
    //    pthread_mutex_unlock(&video_frame_mutex2);
}

- (NSUInteger) frameWidth
{
    return _videoCodecCtx ? _videoCodecCtx->width : 0;
}

- (NSUInteger) frameHeight
{
    return _videoCodecCtx ? _videoCodecCtx->height : 0;
}

- (CGFloat) sampleRate
{
    return _audioCodecCtx ? _audioCodecCtx->sample_rate : 0;
}

- (NSUInteger) audioStreamsCount
{
    return [_audioStreams count];
}

- (NSUInteger) subtitleStreamsCount
{
    return [_subtitleStreams count];
}

- (NSInteger) selectedAudioStream
{
    if (_audioStream == -1)
        return -1;
    NSNumber *n = [NSNumber numberWithInteger:_audioStream];
    return [_audioStreams indexOfObject:n];
}

- (void) setSelectedAudioStream:(NSInteger)selectedAudioStream
{
    NSInteger audioStream = [_audioStreams[selectedAudioStream] integerValue];
    [self closeAudioStream];
    IRMovieError errCode = [self openAudioStream: audioStream];
    if (IRMovieErrorNone != errCode) {
        NSLog(@"%@", errorMessage(errCode));
    }
}

- (NSInteger) selectedSubtitleStream
{
    if (_subtitleStream == -1)
        return -1;
    return [_subtitleStreams indexOfObject:@(_subtitleStream)];
}

- (void) setSelectedSubtitleStream:(NSInteger)selected
{
    [self closeSubtitleStream];
    
    if (selected == -1) {
        
        _subtitleStream = -1;
        
    } else {
        
        NSInteger subtitleStream = [_subtitleStreams[selected] integerValue];
        IRMovieError errCode = [self openSubtitleStream:subtitleStream];
        if (IRMovieErrorNone != errCode) {
            NSLog(@"%@", errorMessage(errCode));
        }
    }
}

- (BOOL) validAudio
{
    return _audioStream != -1;
}

- (BOOL) validVideo
{
    return _videoStream != -1;
}

- (BOOL) validSubtitles
{
    return _subtitleStream != -1;
}

- (NSDictionary *) info
{
    if (!_info) {
        
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        
        if (_formatCtx) {
            
            const char *formatName = _formatCtx->iformat->name;
            [md setValue: [NSString stringWithCString:formatName encoding:NSUTF8StringEncoding]
                  forKey: @"format"];
            
            if (_formatCtx->bit_rate) {
                
                [md setValue: [NSNumber numberWithInt:_formatCtx->bit_rate]
                      forKey: @"bitrate"];
            }
            
            if (_formatCtx->metadata) {
                
                NSMutableDictionary *md1 = [NSMutableDictionary dictionary];
                
                AVDictionaryEntry *tag = NULL;
                while((tag = av_dict_get(_formatCtx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX))) {
                    
                    [md1 setValue: [NSString stringWithCString:tag->value encoding:NSUTF8StringEncoding]
                           forKey: [NSString stringWithCString:tag->key encoding:NSUTF8StringEncoding]];
                }
                
                [md setValue: [md1 copy] forKey: @"metadata"];
            }
            
            char buf[256];
            
            if (_videoStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _videoStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Video: "])
                        s = [s substringFromIndex:@"Video: ".length];
                    [ma addObject:s];
                }
                md[@"video"] = ma.copy;
            }
            
            if (_audioStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _audioStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"%s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Audio: "])
                        s = [s substringFromIndex:@"Audio: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"audio"] = ma.copy;
            }
            
            if (_subtitleStreams.count) {
                NSMutableArray *ma = [NSMutableArray array];
                for (NSNumber *n in _subtitleStreams) {
                    AVStream *st = _formatCtx->streams[n.integerValue];
                    
                    NSMutableString *ms = [NSMutableString string];
                    AVDictionaryEntry *lang = av_dict_get(st->metadata, "language", NULL, 0);
                    if (lang && lang->value) {
                        [ms appendFormat:@"%s ", lang->value];
                    }
                    
                    avcodec_string(buf, sizeof(buf), st->codec, 1);
                    NSString *s = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
                    if ([s hasPrefix:@"Subtitle: "])
                        s = [s substringFromIndex:@"Subtitle: ".length];
                    [ms appendString:s];
                    
                    [ma addObject:ms.copy];
                }
                md[@"subtitles"] = ma.copy;
            }
            
        }
        
        _info = [md copy];
    }
    
    return _info;
}

- (NSString *) videoStreamFormatName
{
    if (!_videoCodecCtx)
        return nil;
    
    if (_videoCodecCtx->pix_fmt == AV_PIX_FMT_NONE)
        return @"";
    
    const char *name = av_get_pix_fmt_name(_videoCodecCtx->pix_fmt);
    return name ? [NSString stringWithCString:name encoding:NSUTF8StringEncoding] : @"?";
}

- (CGFloat) startTime
{
    if (_videoStream != -1) {
        
        AVStream *st = _formatCtx->streams[_videoStream];
        if (AV_NOPTS_VALUE != st->start_time)
            return st->start_time * _videoTimeBase;
        return 0;
    }
    
    if (_audioStream != -1) {
        
        AVStream *st = _formatCtx->streams[_audioStream];
        if (AV_NOPTS_VALUE != st->start_time)
            return st->start_time * _audioTimeBase;
        return 0;
    }
    
    return 0;
}


+ (void)initialize
{
    av_log_set_callback(FFLog);
    av_register_all();
    avformat_network_init();
}

- (id)init {
    if (self=[super init]) {
        pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
        memcpy(&self->video_frame_mutex2, &mutex, sizeof(pthread_mutex_t));
        _dispatchQueue = dispatch_queue_create("IRMovieDecoder", DISPATCH_QUEUE_SERIAL);
        bufferArray = [NSMutableArray new];
        readFrameFinished = YES;
        _framelock = [NSObject new];
        maxBufferDurationForMemoryLeak = 60*60;
        maxBufferDuration = 30;
        minBufferDuration = 3;
    }
    return self;
}

+ (id) movieDecoderWithContentPath: (NSString *) path
                             error: (NSError **) perror
{
    IRMovieDecoder *mp = [[IRMovieDecoder alloc] init];
    if (mp) {
        [mp openFile:path error:perror duration:0];
    }
    return mp;
}

- (void) dealloc
{
    NSLog(@"%@ dealloc", self);
    [self closeFile];
}

#pragma mark - private

- (BOOL) openFile: (NSString *) path
            error: (NSError **) perror
         duration:(int64_t)contextDuration
{
    if (!path) {
        return NO;
    }
    //    NSAssert(path, @"nil path");
    //    NSAssert(!_formatCtx, @"already open");
    
    _isNetwork = isNetworkPath(path);
    
    static BOOL needNetworkInit = YES;
    if (needNetworkInit && _isNetwork) {
        
        needNetworkInit = NO;
        avformat_network_init();
    }
    
    _path = path;
    
    IRMovieError errCode = [self openInput: path];
    
    if (contextDuration > 0) {
        _formatCtx->duration = contextDuration;
    }
    
    if (errCode == IRMovieErrorNone) {
        
        IRMovieError videoErr = [self openVideoStream];
        IRMovieError audioErr = [self openAudioStream];
        //        IRMovieError videoErr = [self openVideoStreamNew];
        //        IRMovieError audioErr = [self openAudioStreamNew];
        
        _subtitleStream = -1;
        
        if (videoErr != IRMovieErrorNone &&
            audioErr != IRMovieErrorNone) {
            
            errCode = videoErr; // both fails
            
        } else {
            
            _subtitleStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_SUBTITLE);
        }
    }
    
    if (errCode != IRMovieErrorNone) {
        
        [self closeFile];
        NSString *errMsg = errorMessage(errCode);
        NSLog(@"%@, %@", errMsg, path.lastPathComponent);
        if (perror)
            *perror = irmovieError(errCode, errMsg);
        return NO;
    }
    
    return YES;
}

- (IRMovieError) openInput: (NSString *) path
{
    AVFormatContext *formatCtx = NULL;
    
    if((formatCtx = [self.delegate attachedAVFormatContext]) == nil){
        if (_interruptCallback) {
            
            formatCtx = avformat_alloc_context();
            if (!formatCtx)
                return IRMovieErrorOpenFile;
            
            AVIOInterruptCB cb = {interrupt_callback, (__bridge void *)(self)};
            formatCtx->interrupt_callback = cb;
        }
        
        //    formatCtx->probesize2 = 32;
        //    formatCtx->max_analyze_duration2 = 32;
        //    formatCtx->max_index_size = 10000000;
        
        //    AVDictionary *stream_opts = 0;
        //    av_dict_set(&stream_opts, "timeout", "10000000", 0);
        //    AVDictionary *opts = 0;
        //    av_dict_set(&opts, "preset", "medium", 0);
        //    av_dict_set(&opts, "crf", "29", 0);
        //    av_dict_set(&opts, "profile", "baseline", 0);
        //    av_dict_set(&opts, "level", "30", 0);
        //    av_dict_set(&opts, "maxrate", "200000", 0);
        //    av_dict_set(&opts, "minrate", "0", 0);
        //    av_dict_set(&opts, "bufsize", "2000000", 0);
        //    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
        
        //    if (avformat_open_input(&formatCtx, [path cStringUsingEncoding: NSUTF8StringEncoding], NULL, &stream_opts) < 0) {
        if (avformat_open_input(&formatCtx, [path cStringUsingEncoding: NSUTF8StringEncoding], NULL, NULL) < 0) {
            if (formatCtx)
                avformat_free_context(formatCtx);
            return IRMovieErrorOpenFile;
        }
        
        //        av_format_inject_global_side_data(formatCtx);
        
        //        AVDictionary *codec_opts = 0;
        //         stream_opts = setup_find_stream_info_opts(formatCtx, codec_opts);
        
        if (avformat_find_stream_info(formatCtx, NULL) < 0) {
            
            avformat_close_input(&formatCtx);
            return IRMovieErrorStreamInfoNotFound;
        }
        
        //        av_dump_format(formatCtx, 0, [path.lastPathComponent cStringUsingEncoding: NSUTF8StringEncoding], false);
    }
    
    _formatCtx = formatCtx;
    return IRMovieErrorNone;
}

//AVDictionary **setup_find_stream_info_opts(AVFormatContext *s,
//                                    AVDictionary *codec_opts)
// {
//         int i;
//         AVDictionary **opts;
//
//         if (!s->nb_streams)
//                 return NULL;
//         opts = av_mallocz_array(s->nb_streams, sizeof(*opts));
//         if (!opts) {
//                 av_log(NULL, AV_LOG_ERROR,
//                                            "Could not alloc memory for stream options.\n");
//                 return NULL;
//             }
//         for (i = 0; i < s->nb_streams; i++)
//                 opts[i] = filter_codec_opts(codec_opts, s->streams[i]->codec->codec_id,
//                                                                                      s, s->streams[i], NULL);
//         return opts;
//     }
//
//AVDictionary *filter_codec_opts(AVDictionary *opts, enum AVCodecID codec_id,
//                                                                 AVFormatContext *s, AVStream *st, AVCodec *codec)
// {
//         AVDictionary    *ret = NULL;
//     AVDictionaryEntry *t = NULL;
//         int            flags = s->oformat ? AV_OPT_FLAG_ENCODING_PARAM
//                                           : AV_OPT_FLAG_DECODING_PARAM;
//         char          prefix = 0;
//         const AVClass    *cc = avcodec_get_class();
//
//         if (!codec)
//                 codec            = s->oformat ? avcodec_find_encoder(codec_id)
//                                               : avcodec_find_decoder(codec_id);
//
//         switch (st->codec->codec_type) {
//                 case AVMEDIA_TYPE_VIDEO:
//                     prefix  = 'v';
//                     flags  |= AV_OPT_FLAG_VIDEO_PARAM;
//                     break;
//                 case AVMEDIA_TYPE_AUDIO:
//                     prefix  = 'a';
//                     flags  |= AV_OPT_FLAG_AUDIO_PARAM;
//                     break;
//                 case AVMEDIA_TYPE_SUBTITLE:
//                     prefix  = 's';
//                     flags  |= AV_OPT_FLAG_SUBTITLE_PARAM;
//                     break;
//             }
//
//         while (t = av_dict_get(opts, "", t, AV_DICT_IGNORE_SUFFIX)) {
//                 char *p = strchr(t->key, ':');
//
//                 /* check stream specification in opt name */
//                 if (p)
//                         switch (check_stream_specifier(s, st, p + 1)) {
//                                 case  1: *p = 0; break;
//                                 case  0:         continue;
//                                 default:         exit_program(1);
//                             }
//
//                 if (av_opt_find(&cc, t->key, NULL, flags, AV_OPT_SEARCH_FAKE_OBJ) ||
//                                      !codec ||
//                                      (codec->priv_class &&
//                                                         av_opt_find(&codec->priv_class, t->key, NULL, flags,
//                                                                                                   AV_OPT_SEARCH_FAKE_OBJ)))
//                         av_dict_set(&ret, t->key, t->value, 0);
//                 else if (t->key[0] == prefix &&
//                                                av_opt_find(&cc, t->key + 1, NULL, flags,
//                                                                                              AV_OPT_SEARCH_FAKE_OBJ))
//                         av_dict_set(&ret, t->key + 1, t->value, 0);
//
//                 if (p)
//                         *p = ':';
//             }
//         return ret;
//     }

- (IRMovieError) openVideoStreamNew
{
    int ret, stream_index;
    AVStream *st;
    AVCodecContext *dec_ctx = NULL;
    AVCodec *dec = NULL;
    AVDictionary *opts = NULL;
    ret = av_find_best_stream(_formatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    stream_index = ret;
    _videoStream = ret;
    st = _formatCtx->streams[_videoStream];
    
    IRMovieError errCode = IRMovieErrorStreamNotFound;
    
    errCode = [self openVideoStream: _videoStream];
    
    
    
    //    for (NSNumber *n in _videoStreams) {
    //
    //        const NSUInteger iStream = n.integerValue;
    //
    //        if (0 == (_formatCtx->streams[iStream]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
    //
    //            errCode = [self openVideoStream: iStream];
    //            if (errCode == IRMovieErrorNone)
    //                break;
    //
    //        } else {
    //
    //            _artworkStream = iStream;
    //        }
    //    }
    
    return errCode;
}

- (IRMovieError) openVideoStream
{
    IRMovieError errCode = IRMovieErrorStreamNotFound;
    _videoStream = -1;
    _artworkStream = -1;
    _videoStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_VIDEO);
    for (NSNumber *n in _videoStreams) {
        
        const NSUInteger iStream = n.integerValue;
        
        if (0 == (_formatCtx->streams[iStream]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
            
            errCode = [self openVideoStream: iStream];
            if (errCode == IRMovieErrorNone)
                break;
            
        } else {
            
            _artworkStream = iStream;
        }
    }
    
    return errCode;
}

//AVHWAccel *ff_find_hwaccel(enum AVCodecID codec_id, enum PixelFormat pix_fmt)
//{
//    AVHWAccel *hwaccel=NULL;
//
//    while((hwaccel= av_hwaccel_next(hwaccel))){
//        if (   hwaccel->id      == codec_id
//            && hwaccel->pix_fmt == pix_fmt)
//            return hwaccel;
//    }
//    return NULL;
//}

- (IRMovieError) openVideoStream: (NSInteger) videoStream
{
    // get a pointer to the codec context for the video stream
    AVCodecContext *codecCtx = _formatCtx->streams[videoStream]->codec;
    
    // find the decoder for the video stream
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    //    av_register_hwaccel(ff_find_hwaccel(codecCtx->codec->id, codecCtx->pix_fmt));
    //    avcodec_register_all();
    //    AVHWAccel * a = ff_find_hwaccel(codecCtx->codec_id, codecCtx->pix_fmt);
    //    if(a != NULL)
    //        av_register_hwaccel(a);
    
    if (!codec)
        return IRMovieErrorCodecNotFound;
    
    // inform the codec that we can handle truncated bitstreams -- i.e.,
    // bitstreams where frame boundaries can fall in the middle of packets
    //if(codec->capabilities & CODEC_CAP_TRUNCATED)
    //    _codecCtx->flags |= CODEC_FLAG_TRUNCATED;
    
    codecCtx->thread_count = 8;
    
    //    AVDictionary *opts = NULL;
    //    av_dict_set(&opts, "refcounted_frames", "1", 0);
    
    // open codec
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return IRMovieErrorOpenCodec;
    
    _videoFrame = av_frame_alloc();
    
    if (!_videoFrame) {
        pthread_mutex_lock(&video_frame_mutex);
        avcodec_close(codecCtx);
        pthread_mutex_unlock(&video_frame_mutex);
        return IRMovieErrorAllocateFrame;
    }
    
    _videoStream = videoStream;
    _videoCodecCtx = codecCtx;
    
    // determine fps
    
    AVStream *st = _formatCtx->streams[_videoStream];
    avStreamFPSTimeBase(st, 0.04, &_fps, &_videoTimeBase);
    
    NSLog(@"video codec size: %d:%d fps: %.3f tb: %f",
                self.frameWidth,
                self.frameHeight,
                _fps,
                _videoTimeBase);
    
    NSLog(@"video start time %f", st->start_time * _videoTimeBase);
    NSLog(@"video disposition %d", st->disposition);
    
    return IRMovieErrorNone;
}

- (IRMovieError) openAudioStreamNew
{
    int ret, stream_index;
    AVStream *st;
    AVCodecContext *dec_ctx = NULL;
    AVCodec *dec = NULL;
    AVDictionary *opts = NULL;
    ret = av_find_best_stream(_formatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    stream_index = ret;
    _audioStream = ret;
    st = _formatCtx->streams[_audioStream];
    
    IRMovieError errCode = IRMovieErrorStreamNotFound;
    
    errCode = [self openAudioStream: _audioStream];
    
    //    IRMovieError errCode = IRMovieErrorStreamNotFound;
    //    _audioStream = -1;
    //    _audioStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    //    for (NSNumber *n in _audioStreams) {
    //
    //        errCode = [self openAudioStream: n.integerValue];
    //        if (errCode == IRMovieErrorNone)
    //            break;
    //    }
    return errCode;
}

- (IRMovieError) openAudioStream
{
    IRMovieError errCode = IRMovieErrorStreamNotFound;
    _audioStream = -1;
    _audioStreams = collectStreams(_formatCtx, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *n in _audioStreams) {
        
        errCode = [self openAudioStream: n.integerValue];
        if (errCode == IRMovieErrorNone)
            break;
    }
    return errCode;
}

- (IRMovieError) openAudioStream: (NSInteger) audioStream
{
    AVCodecContext *codecCtx = _formatCtx->streams[audioStream]->codec;
    
    codecCtx->thread_count = 8;
    
    SwrContext *swrContext = NULL;
    
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if(!codec)
        return IRMovieErrorCodecNotFound;
    
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return IRMovieErrorOpenCodec;
    
    if (!audioCodecIsSupported(codecCtx)) {
        
//        id<IRAudioManager> audioManager = [IRAudioManager audioManager];
//        swrContext = swr_alloc_set_opts(NULL,
//                                        av_get_default_channel_layout(audioManager.numOutputChannels),
//                                        AV_SAMPLE_FMT_S16,
//                                        audioManager.samplingRate,
//                                        av_get_default_channel_layout(codecCtx->channels),
//                                        codecCtx->sample_fmt,
//                                        codecCtx->sample_rate,
//                                        0,
//                                        NULL);
//
//        if (!swrContext ||
//            swr_init(swrContext)) {
//
//            if (swrContext)
//                swr_free(&swrContext);
//            pthread_mutex_lock(&video_frame_mutex);
//            avcodec_close(codecCtx);
//            pthread_mutex_unlock(&video_frame_mutex);
//            return IRMovieErroReSampler;
//        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContext)
            swr_free(&swrContext);
        pthread_mutex_lock(&video_frame_mutex);
        avcodec_close(codecCtx);
        pthread_mutex_unlock(&video_frame_mutex);
        return IRMovieErrorAllocateFrame;
    }
    
    _audioStream = audioStream;
    _audioCodecCtx = codecCtx;
    _swrContext = swrContext;
    
    AVStream *st = _formatCtx->streams[_audioStream];
    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    
    NSLog(@"audio codec smr: %.d fmt: %d chn: %d tb: %f %@",
                _audioCodecCtx->sample_rate,
                _audioCodecCtx->sample_fmt,
                _audioCodecCtx->channels,
                _audioTimeBase,
                _swrContext ? @"resample" : @"");
    
    return IRMovieErrorNone;
}

- (IRMovieError) openSubtitleStream: (NSInteger) subtitleStream
{
    AVCodecContext *codecCtx = _formatCtx->streams[subtitleStream]->codec;
    
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if(!codec)
        return IRMovieErrorCodecNotFound;
    
    const AVCodecDescriptor *codecDesc = avcodec_descriptor_get(codecCtx->codec_id);
    if (codecDesc && (codecDesc->props & AV_CODEC_PROP_BITMAP_SUB)) {
        // Only text based subtitles supported
        return IRMovieErroUnsupported;
    }
    
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return IRMovieErrorOpenCodec;
    
    _subtitleStream = subtitleStream;
    _subtitleCodecCtx = codecCtx;
    
    NSLog(@"subtitle codec: '%s' mode: %d enc: %s",
                 codecDesc->name,
                 codecCtx->sub_charenc_mode,
                 codecCtx->sub_charenc);
    
    _subtitleASSEvents = -1;
    
    if (codecCtx->subtitle_header_size) {
        
        NSString *s = [[NSString alloc] initWithBytes:codecCtx->subtitle_header
                                               length:codecCtx->subtitle_header_size
                                             encoding:NSASCIIStringEncoding];
        
        if (s.length) {
            
            NSArray *fields = [IRMovieSubtitleASSParser parseEvents:s];
            if (fields.count && [fields.lastObject isEqualToString:@"Text"]) {
                _subtitleASSEvents = fields.count;
                NSLog(@"subtitle ass events: %@", [fields componentsJoinedByString:@","]);
            }
        }
    }
    
    return IRMovieErrorNone;
}

-(void) closeFile
{
    NSLog(@"close file");
    if (_formatCtx) {
        //        AVIOInterruptCB icb={interruptCallBack,(__bridge void *)(self)};
        //        AVIOInterruptCB icb={((__bridge) intvoidp)&interruptCallBack,_formatCtx};
        _formatCtx->interrupt_callback.opaque = nil;
        _formatCtx->interrupt_callback.callback = nil;
        //        _formatCtx->interrupt_callback = icb;
        
        //                avformat_close_input(&_formatCtx);
        //                _formatCtx = NULL;
        //                av_free(_videoCodecCtx);
    }else{
        return;
    }
    
    NSLog(@"close file2");
    finished = true;
    pthread_mutex_lock(&video_frame_mutex2);
    //    NSLog(@"pthread_mutex_lock video_frame_mutex2 closeFile");
    [self closeAudioStream];
    
    [self closeVideoStream];
    [self closeSubtitleStream];
    
    
    
    _videoStreams = nil;
    _audioStreams = nil;
    _subtitleStreams = nil;
    
    [self freeBuffered];
    
    if (_formatCtx) {
        
        NSLog(@"lock video_frame_mutex2");
        avformat_close_input(&_formatCtx);
        //        avformat_free_context(_formatCtx);
        _formatCtx = NULL;
        
        NSLog(@"unlock video_frame_mutex2");
    }
    if (_dispatchQueue) {
        // Not needed as of ARC.
        //        dispatch_release(_dispatchQueue);
        _dispatchQueue = NULL;
    }
    
    //    NSLog(@"pthread_mutex_unlock video_frame_mutex2 closeFile");
    pthread_mutex_unlock(&video_frame_mutex2);
    //    int (^interruptCallBack)(void *) = ^(void *ctx){
    //
    //        //    //once your preferred time is out you can return 1 and exit from the loop
    //        //    if(1){
    //        //        //exit
    //        //        return 1;
    //        //    }
    //
    
    
    //
    //        //continue
    //        return 0;
    //
    //    };
    //
    //    typedef int (*intvoidp)(void *);
    
    
}

int interruptCallBack(void *ctx){
    IRMovieDecoder *me = (__bridge IRMovieDecoder *)ctx;
    
    //    //once your preferred time is out you can return 1 and exit from the loop
    //    if(1){
    //        //exit
    //        return 1;
    //    }
    avformat_close_input(&me->_formatCtx);
    //    me->avformat_close_input(&_formatCtx);
    me->_formatCtx = NULL;
    
    //continue
    return 0;
    
}


- (void) closeVideoStream
{
    //    avcodec_close(_formatCtx->streams);
    _videoStream = -1;
    
    [self closeScaler];
    
    pthread_mutex_lock(&video_frame_mutex);
    if (_videoFrame) {
        
        av_free(_videoFrame);
        //        av_frame_free(&_videoFrame);
        //        av_frame_unref(_videoFrame);
        _videoFrame = NULL;
    }
    
    
    
    //    av_free(_picture.data[0]);
    //    av_free(&_picture);
    
    if (_videoCodecCtx) {
        NSLog(@"thread count: %d", _videoCodecCtx->thread_count);
        avcodec_close(_videoCodecCtx);
        //        avcodec_free_context(&_videoCodecCtx);
        
        _videoCodecCtx = NULL;
    }
    pthread_mutex_unlock(&video_frame_mutex);
}

- (void) closeAudioStream
{
    _audioStream = -1;
    
    if (_swrBuffer) {
        
        free(_swrBuffer);
        _swrBuffer = NULL;
        _swrBufferSize = 0;
    }
    
    if (_swrContext) {
        
        swr_free(&_swrContext);
        _swrContext = NULL;
    }
    
    if (_audioFrame) {
        
        av_free(_audioFrame);
        _audioFrame = NULL;
    }
    
    if (_audioCodecCtx) {
        
        avcodec_close(_audioCodecCtx);
        _audioCodecCtx = NULL;
    }
}

- (void) closeSubtitleStream
{
    _subtitleStream = -1;
    
    if (_subtitleCodecCtx) {
        
        avcodec_close(_subtitleCodecCtx);
        _subtitleCodecCtx = NULL;
    }
}

- (void) closeScaler
{
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    
    if (_pictureValid) {
        avpicture_free(&_picture);
        _pictureValid = NO;
    }
}

- (BOOL) setupScaler
{
    [self closeScaler];
    
    _pictureValid = avpicture_alloc(&_picture,
                                    AV_PIX_FMT_RGB24,
                                    _videoCodecCtx->width,
                                    _videoCodecCtx->height) == 0;
    
    if (!_pictureValid)
        return NO;
    
    _swsContext = sws_getCachedContext(_swsContext,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       _videoCodecCtx->pix_fmt,
                                       _videoCodecCtx->width,
                                       _videoCodecCtx->height,
                                       AV_PIX_FMT_RGB24,
                                       SWS_FAST_BILINEAR,
                                       NULL, NULL, NULL);
    
    return _swsContext != NULL;
}

- (IRFFVideoFrame *) handleVideoFrame
{
    IRFFVideoFrame *frame = NULL;
    
    pthread_mutex_lock(&video_frame_mutex);
    
    
    if (!_videoFrame || !_videoFrame->data[0])
        goto end;
    
    if (_videoFrameFormat == IRFrameFormatYUV) {
        
        IRFFAVYUVVideoFrame * yuvFrame = [[IRFFAVYUVVideoFrame alloc] init];
        
//        yuvFrame.luma = copyFrameData(_videoFrame->data[0],
//                                      _videoFrame->linesize[0],
//                                      _videoCodecCtx->width,
//                                      _videoCodecCtx->height);
//
//        yuvFrame.chromaB = copyFrameData(_videoFrame->data[1],
//                                         _videoFrame->linesize[1],
//                                         _videoCodecCtx->width / 2,
//                                         _videoCodecCtx->height / 2);
//
//        yuvFrame.chromaR = copyFrameData(_videoFrame->data[2],
//                                         _videoFrame->linesize[2],
//                                         _videoCodecCtx->width / 2,
//                                         _videoCodecCtx->height / 2);
        
        frame = yuvFrame;
        
    } else {
        
        if (!_swsContext &&
            ![self setupScaler]) {
            
            NSLog(@"fail setup video scaler");
            return nil;
        }
        
        sws_scale(_swsContext,
                  (const uint8_t **)_videoFrame->data,
                  _videoFrame->linesize,
                  0,
                  _videoCodecCtx->height,
                  _picture.data,
                  _picture.linesize);
        
        
        IRVideoFrameRGB *rgbFrame = [[IRVideoFrameRGB alloc] init];
        
        rgbFrame.linesize = _picture.linesize[0];
        rgbFrame.rgb = [NSData dataWithBytes:_picture.data[0]
                                      length:rgbFrame.linesize * _videoCodecCtx->height];
        frame = rgbFrame;
    }
    
    frame.width = _videoCodecCtx->width;
    frame.height = _videoCodecCtx->height;
    frame.position = av_frame_get_best_effort_timestamp(_videoFrame) * _videoTimeBase;
    
    const int64_t frameDuration = av_frame_get_pkt_duration(_videoFrame);
    if (frameDuration) {
        
        frame.duration = frameDuration * _videoTimeBase;
        frame.duration += _videoFrame->repeat_pict * _videoTimeBase * 0.5;
        
        //if (_videoFrame->repeat_pict > 0) {
        //    LoggerVideo(0, @"_videoFrame.repeat_pict %d", _videoFrame->repeat_pict);
        //}
        
    } else {
        
        // sometimes, ffmpeg unable to determine a frame duration
        // as example yuvj420p stream from web camera
        frame.duration = 1.0 / _fps;
    }
    
#if 0
    LoggerVideo(2, @"VFD: %.4f %.4f | %lld ",
                frame.position,
                frame.duration,
                av_frame_get_pkt_pos(_videoFrame));
#endif
    
end:
    
    pthread_mutex_unlock(&video_frame_mutex);
    
    return frame;
}

- (IRFFAudioFrame *) handleAudioFrame
{
    if (!_audioFrame->data[0])
        return nil;
    
//    id<IRAudioManager> audioManager = [IRAudioManager audioManager];
//
//    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSInteger numFrames;
    
    void * audioData;
    
    if (_swrContext) {
        
//        const NSUInteger ratio = MAX(1, audioManager.samplingRate / _audioCodecCtx->sample_rate) *
//        MAX(1, audioManager.numOutputChannels / _audioCodecCtx->channels) * 2;
//
//        const int bufSize = av_samples_get_buffer_size(NULL,
//                                                       audioManager.numOutputChannels,
//                                                       _audioFrame->nb_samples * ratio,
//                                                       AV_SAMPLE_FMT_S16,
//                                                       1);
//
//        if (!_swrBuffer || _swrBufferSize < bufSize) {
//            _swrBufferSize = bufSize;
//            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
//        }
//
//        Byte *outbuf[2] = { _swrBuffer, 0 };
//
//        numFrames = swr_convert(_swrContext,
//                                outbuf,
//                                _audioFrame->nb_samples * ratio,
//                                (const uint8_t **)_audioFrame->data,
//                                _audioFrame->nb_samples);
        
        if (numFrames < 0) {
            NSLog(@"fail resample audio");
            return nil;
        }
        
        //int64_t delay = swr_get_delay(_swrContext, audioManager.samplingRate);
        //if (delay > 0)
        //    LoggerAudio(0, @"resample delay %lld", delay);
        
        audioData = _swrBuffer;
        
    } else {
        
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSAssert(false, @"bucheck, audio format is invalid");
            return nil;
        }
        
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
//    const NSUInteger numElements = numFrames * numChannels;
//    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];
//
//    float scale = 1.0 / (float)INT16_MAX ;
//    vDSP_vflt16((SInt16 *)audioData, 1, data.mutableBytes, 1, numElements);
//    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
//
    IRFFAudioFrame *frame = [[IRFFAudioFrame alloc] init];
//    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
//    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
//    frame.samples = data;
//
//    if (frame.duration == 0) {
//        // sometimes ffmpeg can't determine the duration of audio frame
//        // especially of wma/wmv format
//        // so in this case must compute duration
//        frame.duration = frame.samples.length / (sizeof(float) * numChannels * audioManager.samplingRate);
//    }
    
#if 0
    LoggerAudio(2, @"AFD: %.4f %.4f | %.4f ",
                frame.position,
                frame.duration,
                frame.samples.length / (8.0 * 44100.0));
#endif
    
    return frame;
}

- (IRFFSubtileFrame *) handleSubtitle: (AVSubtitle *)pSubtitle
{
    NSMutableString *ms = [NSMutableString string];
    
    for (NSUInteger i = 0; i < pSubtitle->num_rects; ++i) {
        
        AVSubtitleRect *rect = pSubtitle->rects[i];
        if (rect) {
            
            if (rect->text) { // rect->type == SUBTITLE_TEXT
                
                NSString *s = [NSString stringWithUTF8String:rect->text];
                if (s.length) [ms appendString:s];
                
            } else if (rect->ass && _subtitleASSEvents != -1) {
                
                NSString *s = [NSString stringWithUTF8String:rect->ass];
                if (s.length) {
                    
                    NSArray *fields = [IRMovieSubtitleASSParser parseDialogue:s numFields:_subtitleASSEvents];
                    if (fields.count && [fields.lastObject length]) {
                        
                        s = [IRMovieSubtitleASSParser removeCommandsFromEventText: fields.lastObject];
                        if (s.length) [ms appendString:s];
                    }
                }
            }
        }
    }
    
    if (!ms.length)
        return nil;
    
    IRFFSubtileFrame *frame = [[IRFFSubtileFrame alloc] init];
//    frame.text = [ms copy];
    frame.position = pSubtitle->pts / AV_TIME_BASE + pSubtitle->start_display_time;
    frame.duration = (CGFloat)(pSubtitle->end_display_time - pSubtitle->start_display_time) / 1000.f;
    
#if 0
    NSLog(@"SUB: %.4f %.4f | %@",
                 frame.position,
                 frame.duration,
                 frame.text);
#endif
    
    return frame;
}

- (BOOL) interruptDecoder
{
    if (_interruptCallback)
        return _interruptCallback();
    return NO;
}

#pragma mark - public

- (BOOL) setupVideoFrameFormat: (IRFrameFormat) format
{
    if (format == IRFrameFormatYUV &&
        _videoCodecCtx &&
        (_videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P)) {
        
        _videoFrameFormat = IRFrameFormatYUV;
        return YES;
    }
    
    _videoFrameFormat = IRFrameFormatRGB;
    return _videoFrameFormat == format;
}

int64_t seek_pos;
int64_t seek_rel;
int seek_flags;

/* seek in the stream */
static void stream_seek(int64_t pos, int64_t rel, int seek_by_bytes)
{
    //         if (!seek_req) {
    seek_pos = pos;
    seek_rel = rel;
    seek_flags &= ~AVSEEK_FLAG_BYTE;
    if (seek_by_bytes)
        seek_flags |= AVSEEK_FLAG_BYTE;
    //                 seek_req = 1;
    //                 SDL_CondSignal(is->continue_read_thread);
    //             }
}

-(void) readFrames{
    
    @synchronized(_framelock) {
        if(!readFrameFinished)
            return;
        readFrameFinished = NO;
    }
    
    dispatch_async(_dispatchQueue, ^{
        
        AVPacket packet;
        //        av_init_packet(&packet);
        //        packet.data = NULL;
        //        packet.size = 0;
        
        while (!readFrameFinished && !closeReadFrame) {
            
            if(!justOnce && bufferDuration>=maxBufferDuration)
                break;
            
            
            
            @synchronized(_framelock) {
                if(_formatCtx != nil && _formatCtx != NULL){
                    if (av_read_frame(_formatCtx, &packet) < 0)
                    {
                        _isEOF = YES;
                        NSLog(@"EOF");
                        break;
                    }
                    else{
                        _isEOF = NO;
                    }
                }else{
                    NSLog(@"nil");
                }
            }
            
            if (round(self.position)>=self.duration) {
                _isEOF = YES;
                if(_isEOF){
                    if(packet.stream_index ==_videoStream)
                        break;
                    else if(_videoStream==-1 && packet.stream_index == _audioStream)
                        break;
                    
                }
                //                break;
            }
            
            if(packet.size>0){
                
                
                
                CGFloat packet_s = 0;
                
                if(totalSize >= 0)
                    totalSize += packet.size;
                
                if(packet.stream_index ==_videoStream){
                    packet_s = (CGFloat)(packet.duration * _videoTimeBase);
                    bufferDuration += packet_s;
                }
                
                if(packet.stream_index ==_videoStream){
                    if(packet.pts != AV_NOPTS_VALUE){
                        durationTotal = packet.pts * _videoTimeBase;
                        NSLog(@"packet time:%f ",packet.pts * _videoTimeBase);
                    }else{
                        durationTotal = packet.dts * _videoTimeBase;
                        NSLog(@"packet time:%f ",packet.dts * _videoTimeBase);
                    }
                    
                    //                    durationTotal += packet_s;
                    
                }
                
                if (closeReadFrame==NO) {
                    @synchronized(bufferArray) {
                        [bufferArray addObject:[NSValue value:&packet withObjCType:@encode(AVPacket)]];
                        //                        av_free_packet(&packet);
                    }
                }
            }
            
            if(justOnce)
                break;
        }
        
        if (closeReadFrame) NSLog(@"readFrameFinished");
        
        @synchronized(_framelock) {
            readFrameFinished = YES;
        }
        closeReadFrame = NO;
    });
    //    return packet.size;
}

-(CGFloat)getBufferDuration{
    //    return bufferDuration;
    return durationTotal;
}

-(long long)getTotalSize{
    return totalSize;
}

-(void)receiveMemoryWarning{
    //    if(bufferDuration >= minBufferDuration){
    //        justOnce = false;
    //        maxBufferDuration = minBufferDuration;
    //    }else if(bufferDuration >= minBufferDuration/2){
    //        justOnce = false;
    //        maxBufferDuration = minBufferDuration/2;
    //    }else{
    //        [self stopMaxBufferDuration];
    //    }
    [self stopMaxBufferDuration];
    
    maxBufferDurationForMemoryLeak = bufferDuration;
}

-(void)startMaxBufferDuration{
    justOnce = false;
    //    if(maxBufferDuration + 3 <= maxBufferDurationForMemoryLeak)
    maxBufferDuration = 3;
}

-(void)increaseMaxBufferDuration{
    justOnce = false;
    //    if(maxBufferDuration + 3 <= maxBufferDurationForMemoryLeak)
    maxBufferDuration += 0.1;
}

-(void)stopMaxBufferDuration{
    justOnce = true;
    maxBufferDuration = 1;
}

- (NSArray *) decodeFramesNew: (CGFloat) minDuration
{
    if (_videoStream == -1 &&
        _audioStream == -1)
        return nil;
    
    NSMutableArray *result = [NSMutableArray array];
    
    AVPacket packet;
    
    CGFloat decodedDuration = 0;
    
    finished = NO;
    
    while (!finished) {
        
        pthread_mutex_lock(&video_frame_mutex2);
        //        NSLog(@"pthread_mutex_lock video_frame_mutex2");
        
        @synchronized(bufferArray) {
            if(bufferArray.count==0){
                [self readFrames];
                //                NSLog(@"pthread_mutex_unlock video_frame_mutex2");
                if(bufferArray.count==0)
                    finished = YES;
                pthread_mutex_unlock(&video_frame_mutex2);
                continue;
            }
            [bufferArray[0] getValue:&packet];
            [bufferArray removeObjectAtIndex:0];
        }
        
        if (packet.stream_index ==_videoStream) {
            
            int pktSize = packet.size;
            
            if (pktSize<=0) {
                NSLog(@"pktSize:fail");
            }
            
            while (pktSize > 0) {
                
                int gotframe = 0;
                
                int len = avcodec_decode_video2(_videoCodecCtx,
                                                _videoFrame,
                                                &gotframe,
                                                &packet);
                
                
                if (len < 0) {
                    NSLog(@"decode video error, skip packet");
                    break;
                }
                
                if (gotframe) {
                    
//                    if (!_disableDeinterlacing &&
//                        _videoFrame->interlaced_frame) {
//
//                        avpicture_deinterlace((AVPicture*)_videoFrame,
//                                              (AVPicture*)_videoFrame,
//                                              _videoCodecCtx->pix_fmt,
//                                              _videoCodecCtx->width,
//                                              _videoCodecCtx->height);
//                    }
                    
                    IRFFVideoFrame *frame = [self handleVideoFrame];
                    if (frame) {
                        [result addObject:frame];
                        
                        _position = frame.position;
                        decodedDuration += frame.duration;
                        if (decodedDuration > minDuration)
                            finished = YES;
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
                //                NSLog(@"pktSize:%d",pktSize);
            }
            
            bufferDuration -= (packet.duration * _videoTimeBase);
            
        } else if (packet.stream_index == _audioStream) {
            
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    NSLog(@"decode audio error, skip packet");
                    break;
                }
                
                if (gotframe) {
                    
                    IRFFAudioFrame * frame = [self handleAudioFrame];
                    if (frame) {
                        
                        [result addObject:frame];
                        
                        if (_videoStream == -1) {
                            
                            _position = frame.position;
                            decodedDuration += frame.duration;
                            if (decodedDuration > minDuration)
                                finished = YES;
                        }
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
            
            //            bufferDuration -= packet.duration * _videoTimeBase;
            
        } else if (packet.stream_index == _artworkStream) {
            
            if (packet.size) {
                
                IRFFArtworkFrame *frame = [[IRFFArtworkFrame alloc] init];
                frame.picture = [NSData dataWithBytes:packet.data length:packet.size];
                [result addObject:frame];
            }
            
            //            bufferDuration -= packet.duration * _videoTimeBase;
            
        } else if (packet.stream_index == _subtitleStream) {
            
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                
                AVSubtitle subtitle;
                int gotsubtitle = 0;
                int len = avcodec_decode_subtitle2(_subtitleCodecCtx,
                                                   &subtitle,
                                                   &gotsubtitle,
                                                   &packet);
                
                if (len < 0) {
                    NSLog(@"decode subtitle error, skip packet");
                    break;
                }
                
                if (gotsubtitle) {
                    
                    IRFFSubtileFrame *frame = [self handleSubtitle: &subtitle];
                    if (frame) {
                        [result addObject:frame];
                    }
                    avsubtitle_free(&subtitle);
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
            
            //            bufferDuration -= packet.duration * _videoTimeBase;
        }
        
        av_free_packet(&packet);
        //        NSLog(@"pthread_mutex_unlock video_frame_mutex2");
        pthread_mutex_unlock(&video_frame_mutex2);
    }
    //    NSLog(@"pthread_mutex_unlock video_frame_mutex2");
    pthread_mutex_unlock(&video_frame_mutex2);
    return result;
}

- (void) freeBuffered{
    NSLog(@"freeBuffered");
    finished = true;
    //    pthread_mutex_lock(&video_frame_mutex2);
    //    NSLog(@"pthread_mutex_lock video_frame_mutex2 freeBuffered");
    @synchronized(_framelock){
        readFrameFinished = false;
    }
    closeReadFrame = true;
    //    while(!readFrameFinished){
    //        sleep(0.5);
    //    }
    //
    //    @synchronized(bufferArray) {
    //        [bufferArray removeAllObjects];
    //        bufferDuration = 0;
    //    }
    
    //    dispatch_sync(_dispatchQueue, ^{
    //        NSLog(@"freeBuffered 2");
    @synchronized(bufferArray) {
        [bufferArray removeAllObjects];
        bufferDuration = 0;
        durationTotal = 0;
        //            NSLog(@"freeBuffered bufferArray");
    }
    @synchronized(_framelock){
        //            NSLog(@"freeBuffered readFrameFinished");
        readFrameFinished = true;
    }
    //        NSLog(@"freeBuffered 3");
    //        dispatch_sync(dispatch_get_main_queue(), ^{
    //            NSLog(@"pthread_mutex_unlock video_frame_mutex2 freeBuffered");
    //        });
    //    });
    
    //    pthread_mutex_unlock(&video_frame_mutex2);
}

@end

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

static int interrupt_callback(void *ctx)
{
    if (!ctx)
        return 0;
    __unsafe_unretained IRMovieDecoder *p = (__bridge IRMovieDecoder *)ctx;
    const BOOL r = [p interruptDecoder];
    if (r) NSLog(@"DEBUG: INTERRUPT_CALLBACK!");
    return r;
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

@implementation IRMovieSubtitleASSParser

+ (NSArray *) parseEvents: (NSString *) events
{
    NSRange r = [events rangeOfString:@"[Events]"];
    if (r.location != NSNotFound) {
        
        NSUInteger pos = r.location + r.length;
        
        r = [events rangeOfString:@"Format:"
                          options:0
                            range:NSMakeRange(pos, events.length - pos)];
        
        if (r.location != NSNotFound) {
            
            pos = r.location + r.length;
            r = [events rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                        options:0
                                          range:NSMakeRange(pos, events.length - pos)];
            
            if (r.location != NSNotFound) {
                
                NSString *format = [events substringWithRange:NSMakeRange(pos, r.location - pos)];
                NSArray *fields = [format componentsSeparatedByString:@","];
                if (fields.count > 0) {
                    
                    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
                    NSMutableArray *ma = [NSMutableArray array];
                    for (NSString *s in fields) {
                        [ma addObject:[s stringByTrimmingCharactersInSet:ws]];
                    }
                    return ma;
                }
            }
        }
    }
    
    return nil;
}

+ (NSArray *) parseDialogue: (NSString *) dialogue
                  numFields: (NSUInteger) numFields
{
    if ([dialogue hasPrefix:@"Dialogue:"]) {
        
        NSMutableArray *ma = [NSMutableArray array];
        
        NSRange r = {@"Dialogue:".length, 0};
        NSUInteger n = 0;
        
        while (r.location != NSNotFound && n++ < numFields) {
            
            const NSUInteger pos = r.location + r.length;
            
            r = [dialogue rangeOfString:@","
                                options:0
                                  range:NSMakeRange(pos, dialogue.length - pos)];
            
            const NSUInteger len = r.location == NSNotFound ? dialogue.length - pos : r.location - pos;
            NSString *p = [dialogue substringWithRange:NSMakeRange(pos, len)];
            p = [p stringByReplacingOccurrencesOfString:@"\\N" withString:@"\n"];
            [ma addObject: p];
        }
        
        return ma;
    }
    
    return nil;
}

+ (NSString *) removeCommandsFromEventText: (NSString *) text
{
    NSMutableString *ms = [NSMutableString string];
    
    NSScanner *scanner = [NSScanner scannerWithString:text];
    while (!scanner.isAtEnd) {
        
        NSString *s;
        if ([scanner scanUpToString:@"{\\" intoString:&s]) {
            
            [ms appendString:s];
        }
        
        if (!([scanner scanString:@"{\\" intoString:nil] &&
              [scanner scanUpToString:@"}" intoString:nil] &&
              [scanner scanString:@"}" intoString:nil])) {
            
            break;
        }
    }
    
    return ms;
}

@end

static void FFLog(void* context, int level, const char* format, va_list args) {
    @autoreleasepool {
        //Trim time at the beginning and new line at the end
        NSString* message = [[NSString alloc] initWithFormat: [NSString stringWithUTF8String: format] arguments: args];
        switch (level) {
            case 0:
            case 1:
                NSLog(@"%@", [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
                break;
            case 2:
                NSLog(@"%@", [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
                break;
            case 3:
            case 4:
                NSLog(@"%@", [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
                break;
            default:
                //                LoggerStream(3, @"%@", [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
                break;
        }
    }
}

