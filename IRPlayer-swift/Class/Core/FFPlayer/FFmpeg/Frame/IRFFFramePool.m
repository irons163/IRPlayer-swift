//
//  IRFFFramePool.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFFramePool.h"
#import "IRPlayerMacro.h"

@interface IRFFFramePool () <IRFFFrameDelegate>

@property (nonatomic, copy) Class frameClassName;
@property (nonatomic, strong) NSLock * lock;
@property (nonatomic, strong) IRFFFrame * playingFrame;
@property (nonatomic, strong) NSMutableSet <IRFFFrame *> * unuseFrames;
@property (nonatomic, strong) NSMutableSet <IRFFFrame *> * usedFrames;

@end

@implementation IRFFFramePool

+ (instancetype)videoPool
{
    return [self poolWithCapacity:60 frameClassName:NSClassFromString(@"IRFFAVYUVVideoFrame")];
}

+ (instancetype)audioPool
{
    return [self poolWithCapacity:500 frameClassName:NSClassFromString(@"IRFFAudioFrame")];
}

+ (instancetype)poolWithCapacity:(NSUInteger)number frameClassName:(Class)frameClassName
{
    return [[self alloc] initWithCapacity:number frameClassName:frameClassName];
}

- (instancetype)initWithCapacity:(NSUInteger)number frameClassName:(Class)frameClassName
{
    if (self = [super init]) {
        self.frameClassName = frameClassName;
        self.lock = [[NSLock alloc] init];
        self.unuseFrames = [NSMutableSet setWithCapacity:number];
        self.usedFrames = [NSMutableSet setWithCapacity:number];
    }
    return self;
}

- (NSUInteger)count
{
    return [self unuseCount] + [self usedCount] + (self.playingFrame ? 1 : 0);
}

- (NSUInteger)unuseCount
{
    return self.unuseFrames.count;
}

- (NSUInteger)usedCount
{
    return self.usedFrames.count;
}

- (__kindof IRFFFrame *)getUnuseFrame
{
    [self.lock lock];
    IRFFFrame * frame;
    if (self.unuseFrames.count > 0) {
        frame = [self.unuseFrames anyObject];
        [self.unuseFrames removeObject:frame];
        [self.usedFrames addObject:frame];
        
    } else {
        frame = [[self.frameClassName alloc] init];
        frame.delegate = self;
        [self.usedFrames  addObject:frame];
    }
    [self.lock unlock];
    return frame;
}

- (void)setFrameUnuse:(IRFFFrame *)frame
{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClassName]) return;
    [self.lock lock];
    [self.unuseFrames addObject:frame];
    [self.usedFrames removeObject:frame];
    [self.lock unlock];
}

- (void)setFramesUnuse:(NSArray <IRFFFrame *> *)frames
{
    if (frames.count <= 0) return;
    [self.lock lock];
    for (IRFFFrame * obj in frames) {
        if (![obj isKindOfClass:self.frameClassName]) continue;
        [self.usedFrames removeObject:obj];
        [self.unuseFrames addObject:obj];
    }
    [self.lock unlock];
}

- (void)setFrameStartDrawing:(IRFFFrame *)frame
{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClassName]) return;
    [self.lock lock];
    if (self.playingFrame) {
        [self.unuseFrames addObject:self.playingFrame];
    }
    self.playingFrame = frame;
    [self.usedFrames removeObject:self.playingFrame];
    [self.lock unlock];
}

- (void)setFrameStopDrawing:(IRFFFrame *)frame
{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClassName]) return;
    [self.lock lock];
    if (self.playingFrame == frame) {
        [self.unuseFrames addObject:self.playingFrame];
        self.playingFrame = nil;
    }
    [self.lock unlock];
}

- (void)flush
{
    [self.lock lock];
    [self.usedFrames enumerateObjectsUsingBlock:^(IRFFFrame * _Nonnull obj, BOOL * _Nonnull stop) {
        [self.unuseFrames addObject:obj];
    }];
    [self.usedFrames removeAllObjects];
    [self.lock unlock];
}

#pragma mark - IRFFFrameDelegate

- (void)frameDidStartPlaying:(IRFFFrame *)frame
{
    [self setFrameStartDrawing:frame];
}

- (void)frameDidStopPlaying:(IRFFFrame *)frame
{
    [self setFrameStopDrawing:frame];
}

- (void)frameDidCancel:(IRFFFrame *)frame
{
    [self setFrameUnuse:frame];
}

- (void)dealloc
{
    IRPlayerLog(@"IRFFFramePool release");
}

@end
