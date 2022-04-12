//
//  IRFFAVYUVVideoFrame.h
//  IRPlayer
//
//  Created by Phil on 2019/10/25.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFVideoFrame.h"

struct AVFrame;

NS_ASSUME_NONNULL_BEGIN

// FFmpeg AVFrame YUV frame
@interface IRFFAVYUVVideoFrame : IRFFVideoFrame

{
@public
    UInt8 * channel_pixels[IRYUVChannelCount];
}

@property (nonatomic) UInt8 *luma;
@property (nonatomic) UInt8 *chromaB;
@property (nonatomic) UInt8 *chromaR;

+ (instancetype)videoFrame;
- (void)setFrameData:(struct AVFrame *)frame width:(int)width height:(int)height;

- (IRPLFImage)image;

@end

NS_ASSUME_NONNULL_END
