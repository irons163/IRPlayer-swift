//
//  IRFFFramePool.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFFrame.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFFramePool : NSObject

+ (instancetype)videoPool;
+ (instancetype)audioPool;
+ (instancetype)poolWithCapacity:(NSUInteger)number frameClassName:(Class)frameClassName;

- (NSUInteger)count;
- (NSUInteger)unuseCount;
- (NSUInteger)usedCount;

- (__kindof IRFFFrame *)getUnuseFrame;

- (void)flush;

@end

NS_ASSUME_NONNULL_END
