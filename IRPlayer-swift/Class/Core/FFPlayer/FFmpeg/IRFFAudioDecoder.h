//
//  IRFFAudioDecoder.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFAudioFrame.h"
#import "avformat.h"

NS_ASSUME_NONNULL_BEGIN

@class IRFFAudioDecoder;

@protocol IRFFAudioDecoderDelegate <NSObject>

- (void)audioDecoder:(IRFFAudioDecoder *)audioDecoder samplingRate:(Float64 *)samplingRate;
- (void)audioDecoder:(IRFFAudioDecoder *)audioDecoder channelCount:(UInt32 *)channelCount;

@end

@interface IRFFAudioDecoder : NSObject

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codec_context timebase:(NSTimeInterval)timebase delegate:(id <IRFFAudioDecoderDelegate>)delegate;

@property (nonatomic, weak) id <IRFFAudioDecoderDelegate> delegate;

- (int)size;
- (BOOL)empty;
- (NSTimeInterval)duration;

- (IRFFAudioFrame *)getFrameSync;
- (int)putPacket:(AVPacket)packet;

- (void)flush;
- (void)destroy;

@end


NS_ASSUME_NONNULL_END
