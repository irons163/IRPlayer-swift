//
//  IRFFVideoToolBox.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "avformat.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFVideoToolBox : NSObject

+ (instancetype)videoToolBoxWithCodecContext:(AVCodecContext *)codecContext;

- (BOOL)sendPacket:(AVPacket)packet;
- (CVImageBufferRef)imageBuffer;

- (BOOL)trySetupVTSession;
- (void)flush;

@end


NS_ASSUME_NONNULL_END
