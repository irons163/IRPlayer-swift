//
//  IRFFAVYUVVideoFrame.m
//  IRPlayer
//
//  Created by Phil on 2019/10/25.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFAVYUVVideoFrame.h"
#import "IRFFTools.h"
#import "IRYUVTools.h"

@interface IRFFAVYUVVideoFrame ()

{
    enum AVPixelFormat pixelFormat;
    
    size_t channel_pixels_buffer_size[IRYUVChannelCount];
    int channel_lenghts[IRYUVChannelCount];
    int channel_linesize[IRYUVChannelCount];
}

@property (nonatomic, strong) NSLock * lock;

@end

@implementation IRFFAVYUVVideoFrame

- (IRFFFrameType)type
{
    return IRFFFrameTypeAVYUVVideo;
}

+ (instancetype)videoFrame
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        channel_lenghts[IRYUVChannelLuma] = 0;
        channel_lenghts[IRYUVChannelChromaB] = 0;
        channel_lenghts[IRYUVChannelChromaR] = 0;
        channel_pixels_buffer_size[IRYUVChannelLuma] = 0;
        channel_pixels_buffer_size[IRYUVChannelChromaB] = 0;
        channel_pixels_buffer_size[IRYUVChannelChromaR] = 0;
        channel_linesize[IRYUVChannelLuma] = 0;
        channel_linesize[IRYUVChannelChromaB] = 0;
        channel_linesize[IRYUVChannelChromaR] = 0;
        channel_pixels[IRYUVChannelLuma] = NULL;
        channel_pixels[IRYUVChannelChromaB] = NULL;
        channel_pixels[IRYUVChannelChromaR] = NULL;
        self.lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)setFrameData:(AVFrame *)frame width:(int)width height:(int)height
{
    pixelFormat = frame->format;
    
    self.width = width;
    self.height = height;
    
    int linesize_y = frame->linesize[IRYUVChannelLuma];
    int linesize_u = frame->linesize[IRYUVChannelChromaB];
    int linesize_v = frame->linesize[IRYUVChannelChromaR];
    
    channel_linesize[IRYUVChannelLuma] = linesize_y;
    channel_linesize[IRYUVChannelChromaB] = linesize_u;
    channel_linesize[IRYUVChannelChromaR] = linesize_v;
    
    UInt8 * buffer_y = channel_pixels[IRYUVChannelLuma];
    UInt8 * buffer_u = channel_pixels[IRYUVChannelChromaB];
    UInt8 * buffer_v = channel_pixels[IRYUVChannelChromaR];
    
    size_t buffer_size_y = channel_pixels_buffer_size[IRYUVChannelLuma];
    size_t buffer_size_u = channel_pixels_buffer_size[IRYUVChannelChromaB];
    size_t buffer_size_v = channel_pixels_buffer_size[IRYUVChannelChromaR];
    
    int need_size_y = IRYUVChannelFilterNeedSize(linesize_y, width, height, 1);
    channel_lenghts[IRYUVChannelLuma] = need_size_y;
    if (buffer_size_y < need_size_y) {
        if (buffer_size_y > 0 && buffer_y != NULL) {
            free(buffer_y);
        }
        channel_pixels_buffer_size[IRYUVChannelLuma] = need_size_y;
        channel_pixels[IRYUVChannelLuma] = malloc(need_size_y);
    }
    int need_size_u = IRYUVChannelFilterNeedSize(linesize_u, width / 2, height / 2, 1);
    channel_lenghts[IRYUVChannelChromaB] = need_size_u;
    if (buffer_size_u < need_size_u) {
        if (buffer_size_u > 0 && buffer_u != NULL) {
            free(buffer_u);
        }
        channel_pixels_buffer_size[IRYUVChannelChromaB] = need_size_u;
        channel_pixels[IRYUVChannelChromaB] = malloc(need_size_u);
    }
    int need_size_v = IRYUVChannelFilterNeedSize(linesize_v, width / 2, height / 2, 1);
    channel_lenghts[IRYUVChannelChromaR] = need_size_v;
    if (buffer_size_v < need_size_v) {
        if (buffer_size_v > 0 && buffer_v != NULL) {
            free(buffer_v);
        }
        channel_pixels_buffer_size[IRYUVChannelChromaR] = need_size_v;
        channel_pixels[IRYUVChannelChromaR] = malloc(need_size_v);
    }
    
    IRYUVChannelFilter(frame->data[IRYUVChannelLuma],
                       linesize_y,
                       width,
                       height,
                       channel_pixels[IRYUVChannelLuma],
                       channel_pixels_buffer_size[IRYUVChannelLuma],
                       1);
    IRYUVChannelFilter(frame->data[IRYUVChannelChromaB],
                       linesize_u,
                       width / 2,
                       height / 2,
                       channel_pixels[IRYUVChannelChromaB],
                       channel_pixels_buffer_size[IRYUVChannelChromaB],
                       1);
    IRYUVChannelFilter(frame->data[IRYUVChannelChromaR],
                       linesize_v,
                       width / 2,
                       height / 2,
                       channel_pixels[IRYUVChannelChromaR],
                       channel_pixels_buffer_size[IRYUVChannelChromaR],
                       1);
}

- (UInt8 *)luma {
    return channel_pixels[IRYUVChannelLuma];
}

- (UInt8 *)chromaB {
    return channel_pixels[IRYUVChannelChromaB];
}

- (UInt8 *)chromaR {
    return channel_pixels[IRYUVChannelChromaR];
}

- (void)flush
{
    self.width = 0;
    self.height = 0;
    channel_lenghts[IRYUVChannelLuma] = 0;
    channel_lenghts[IRYUVChannelChromaB] = 0;
    channel_lenghts[IRYUVChannelChromaR] = 0;
    channel_linesize[IRYUVChannelLuma] = 0;
    channel_linesize[IRYUVChannelChromaB] = 0;
    channel_linesize[IRYUVChannelChromaR] = 0;
    if (channel_pixels[IRYUVChannelLuma] != NULL && channel_pixels_buffer_size[IRYUVChannelLuma] > 0) {
        memset(channel_pixels[IRYUVChannelLuma], 0, channel_pixels_buffer_size[IRYUVChannelLuma]);
    }
    if (channel_pixels[IRYUVChannelChromaB] != NULL && channel_pixels_buffer_size[IRYUVChannelChromaB] > 0) {
        memset(channel_pixels[IRYUVChannelChromaB], 0, channel_pixels_buffer_size[IRYUVChannelChromaB]);
    }
    if (channel_pixels[IRYUVChannelChromaR] != NULL && channel_pixels_buffer_size[IRYUVChannelChromaR] > 0) {
        memset(channel_pixels[IRYUVChannelChromaR], 0, channel_pixels_buffer_size[IRYUVChannelChromaR]);
    }
}

- (void)stopPlaying
{
    [self.lock lock];
    [super stopPlaying];
    [self.lock unlock];
}

- (IRPLFImage)image
{
    [self.lock lock];
    IRPLFImage image = IRYUVConvertToImage(channel_pixels, channel_linesize, self.width, self.height, pixelFormat);
    [self.lock unlock];
    return image;
}

- (int)size
{
    return (int)(channel_lenghts[IRYUVChannelLuma] + channel_lenghts[IRYUVChannelChromaB] + channel_lenghts[IRYUVChannelChromaR]);
}

- (void)dealloc
{
    if (channel_pixels[IRYUVChannelLuma] != NULL && channel_pixels_buffer_size[IRYUVChannelLuma] > 0) {
        free(channel_pixels[IRYUVChannelLuma]);
    }
    if (channel_pixels[IRYUVChannelChromaB] != NULL && channel_pixels_buffer_size[IRYUVChannelChromaB] > 0) {
        free(channel_pixels[IRYUVChannelChromaB]);
    }
    if (channel_pixels[IRYUVChannelChromaR] != NULL && channel_pixels_buffer_size[IRYUVChannelChromaR] > 0) {
        free(channel_pixels[IRYUVChannelChromaR]);
    }
}

@end
