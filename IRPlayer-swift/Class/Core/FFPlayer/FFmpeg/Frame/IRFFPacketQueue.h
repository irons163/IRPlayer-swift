//
//  IRFFPacketQueue.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "avformat.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFPacketQueue : NSObject

+ (instancetype)packetQueueWithTimebase:(NSTimeInterval)timebase;

@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) int size;
@property (atomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval timebase;

- (void)putPacket:(AVPacket)packet duration:(NSTimeInterval)duration;
- (AVPacket)getPacket;

- (void)flush;
- (void)destroy;

@end

NS_ASSUME_NONNULL_END
