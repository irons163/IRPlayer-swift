//
//  IRFFVideoDecoder.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFVideoFrame.h"
#import "avformat.h"

@class IRFFVideoDecoder;

NS_ASSUME_NONNULL_BEGIN

@protocol IRFFVideoDecoderDlegate <NSObject>

- (void)videoDecoder:(IRFFVideoDecoder *)videoDecoder didError:(NSError *)error;
- (void)videoDecoderNeedUpdateBufferedDuration:(IRFFVideoDecoder *)videoDecoder;
- (void)videoDecoderNeedCheckBufferingStatus:(IRFFVideoDecoder *)videoDecoder;

@end

@interface IRFFVideoDecoder : NSObject

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codec_context
                               timebase:(NSTimeInterval)timebase
                                    fps:(NSTimeInterval)fps
                               delegate:(id <IRFFVideoDecoderDlegate>)delegate;

@property (nonatomic, weak) id <IRFFVideoDecoderDlegate> delegate;

@property (nonatomic, assign) BOOL videoToolBoxEnable;      // default is YES;
@property (nonatomic, assign) NSTimeInterval maxDecodeDuration;     // default is 2s;

@property (nonatomic, assign) NSTimeInterval timebase;
@property (nonatomic, assign) NSTimeInterval fps;

@property (nonatomic, strong, readonly) NSError * error;
@property (nonatomic, assign, readonly) BOOL decoding;

@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL endOfFile;

- (int)packetSize;

- (BOOL)empty;
- (BOOL)packetEmpty;
- (BOOL)frameEmpty;

- (NSTimeInterval)duration;
- (NSTimeInterval)packetDuration;
- (NSTimeInterval)frameDuration;

- (IRFFVideoFrame *)getFrameSync;
- (IRFFVideoFrame *)getFrameAsync;

- (void)putPacket:(AVPacket)packet;

- (void)flush;
- (void)destroy;

- (void)decodeFrameThread;

@end

NS_ASSUME_NONNULL_END
