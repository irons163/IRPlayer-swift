//
//  IRPlayerAction.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <IRPlayer_swift/IRPlayer_swift-Swift.h>
#import "IRPlayerAction.h"
//#import "IRPlayer_swift-Swift.h"


// notification name
NSString * const IRPlayerErrorNotificationName = @"IRPlayerErrorNotificationName";                   // player error
NSString * const IRPlayerStateChangeNotificationName = @"IRPlayerStateChangeNotificationName";     // player state change
NSString * const IRPlayerProgressChangeNotificationName = @"IRPlayerProgressChangeNotificationName";  // player play progress change
NSString * const IRPlayerPlayableChangeNotificationName = @"IRPlayerPlayableChangeNotificationName";   // player playable progress change

// notification userinfo key
NSString * const IRPlayerErrorKey = @"error";               // error

NSString * const IRPlayerStatePreviousKey = @"previous";    // state
NSString * const IRPlayerStateCurrentKey = @"current";      // state

NSString * const IRPlayerProgressPercentKey = @"percent";   // progress
NSString * const IRPlayerProgressCurrentKey = @"current";   // progress
NSString * const IRPlayerProgressTotalKey = @"total";       // progress

NSString * const IRPlayerPlayablePercentKey = @"percent";   // playable
NSString * const IRPlayerPlayableCurrentKey = @"current";   // playable
NSString * const IRPlayerPlayableTotalKey = @"total";       // playable




#pragma mark - IRPlayer Action Category

@implementation IRPlayerImp (IRPlayerAction)

- (void)registerPlayerNotificationTarget:(id)target
                             stateAction:(nullable SEL)stateAction
                          progressAction:(nullable SEL)progressAction
                          playableAction:(nullable SEL)playableAction
{
    [self registerPlayerNotificationTarget:target
                               stateAction:stateAction
                            progressAction:progressAction
                            playableAction:playableAction
                               errorAction:nil];
}

- (void)registerPlayerNotificationTarget:(id)target
                             stateAction:(nullable SEL)stateAction
                          progressAction:(nullable SEL)progressAction
                          playableAction:(nullable SEL)playableAction
                             errorAction:(nullable SEL)errorAction
{
    if (!target) return;
    [self removePlayerNotificationTarget:target];
    
    if (stateAction) {
        [[NSNotificationCenter defaultCenter] addObserver:target selector:stateAction name:IRPlayerStateChangeNotificationName object:self];
    }
    if (progressAction) {
        [[NSNotificationCenter defaultCenter] addObserver:target selector:progressAction name:IRPlayerProgressChangeNotificationName object:self];
    }
    if (playableAction) {
        [[NSNotificationCenter defaultCenter] addObserver:target selector:playableAction name:IRPlayerPlayableChangeNotificationName object:self];
    }
    if (errorAction) {
        [[NSNotificationCenter defaultCenter] addObserver:target selector:errorAction name:IRPlayerErrorNotificationName object:self];
    }
}

- (void)removePlayerNotificationTarget:(id)target
{
    [[NSNotificationCenter defaultCenter] removeObserver:target name:IRPlayerStateChangeNotificationName object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:target name:IRPlayerProgressChangeNotificationName object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:target name:IRPlayerPlayableChangeNotificationName object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:target name:IRPlayerErrorNotificationName object:self];
}

@end


#pragma mark - IRPlayer Action Models

@implementation IRModel

+ (IRState *)stateFromUserInfo:(NSDictionary *)userInfo
{
    IRState * state = [[IRState alloc] init];
    state.previous = [[userInfo objectForKey:IRPlayerStatePreviousKey] integerValue];
    state.current = [[userInfo objectForKey:IRPlayerStateCurrentKey] integerValue];
    return state;
}

+ (IRProgress *)progressFromUserInfo:(NSDictionary *)userInfo
{
    IRProgress * progress = [[IRProgress alloc] init];
    progress.percent = [[userInfo objectForKey:IRPlayerProgressPercentKey] doubleValue];
    progress.current = [[userInfo objectForKey:IRPlayerProgressCurrentKey] doubleValue];
    progress.total = [[userInfo objectForKey:IRPlayerProgressTotalKey] doubleValue];
    return progress;
}

+ (IRPlayable *)playableFromUserInfo:(NSDictionary *)userInfo
{
    IRPlayable * playable = [[IRPlayable alloc] init];
    playable.percent = [[userInfo objectForKey:IRPlayerPlayablePercentKey] doubleValue];
    playable.current = [[userInfo objectForKey:IRPlayerPlayableCurrentKey] doubleValue];
    playable.total = [[userInfo objectForKey:IRPlayerPlayableTotalKey] doubleValue];
    return playable;
}

+ (IRError *)errorFromUserInfo:(NSDictionary *)userInfo
{
    IRError * error = [userInfo objectForKey:IRPlayerErrorKey];
    if ([error isKindOfClass:[IRError class]]) {
        return error;
    } else if ([error isKindOfClass:[NSError class]]) {
        IRError * obj = [[IRError alloc] init];
        obj.error = (NSError *)error;
        return obj;
    } else {
        IRError * obj = [[IRError alloc] init];
        obj.error = [NSError errorWithDomain:@"IRPlayer error" code:-1 userInfo:nil];
        return obj;
    }
}

@end

@implementation IRState
@end

@implementation IRProgress
@end

@implementation IRPlayable
@end

@implementation IRErrorEvent
@end

@implementation IRError
@end

