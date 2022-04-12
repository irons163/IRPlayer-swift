//
//  IRFFFrameQueue.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFFrame.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFFrameQueue : NSObject

+ (instancetype)frameQueue;

+ (NSTimeInterval)maxVideoDuration;

+ (NSTimeInterval)sleepTimeIntervalForFull;
+ (NSTimeInterval)sleepTimeIntervalForFullAndPaused;

@property (nonatomic, assign, readonly) int size;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (atomic, assign, readonly) NSTimeInterval duration;

- (void)putFrame:(__kindof IRFFFrame *)frame;
- (void)putSortFrame:(__kindof IRFFFrame *)frame;
- (__kindof IRFFFrame *)getFrameSync;
- (__kindof IRFFFrame *)getFrameAsync;

- (void)flush;
- (void)destroy;

@end

NS_ASSUME_NONNULL_END
