//
//  IRPlayerNotification.m
//  IRPlayer
//
//  Created by Phil on 2019/7/9.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <IRPlayer_swift/IRPlayer_swift-Swift.h>
#import "IRPlayerNotification.h"

@interface IRPlayerImp (IRPlayerNotification)
@property (nonatomic, strong, nullable) IRError * error;
@end

@implementation IRPlayerNotification

+ (void)postPlayer:(IRPlayerImp *)player error:(IRError *)error
{
    if (!player || !error) return;
    NSDictionary * userInfo = @{
                                IRPlayerErrorKey : error
                                };
    player.error = error;
    [self postNotificationName:IRPlayerErrorNotificationName object:player userInfo:userInfo];
}

+ (void)postPlayer:(IRPlayerImp *)player statePrevious:(IRPlayerState)previous current:(IRPlayerState)current
{
    if (!player) return;
    NSDictionary * userInfo = @{
                                IRPlayerStatePreviousKey : @(previous),
                                IRPlayerStateCurrentKey : @(current)
                                };
    [self postNotificationName:IRPlayerStateChangeNotificationName object:player userInfo:userInfo];
}

+ (void)postPlayer:(IRPlayerImp *)player progressPercent:(NSNumber *)percent current:(NSNumber *)current total:(NSNumber *)total
{
    if (!player) return;
    if (![percent isKindOfClass:[NSNumber class]]) percent = @(0);
    if (![current isKindOfClass:[NSNumber class]]) current = @(0);
    if (![total isKindOfClass:[NSNumber class]]) total = @(0);
    NSDictionary * userInfo = @{
                                IRPlayerProgressPercentKey : percent,
                                IRPlayerProgressCurrentKey : current,
                                IRPlayerProgressTotalKey : total
                                };
    [self postNotificationName:IRPlayerProgressChangeNotificationName object:player userInfo:userInfo];
}

+ (void)postPlayer:(IRPlayerImp *)player playablePercent:(NSNumber *)percent current:(NSNumber *)current total:(NSNumber *)total
{
    if (!player) return;
    if (![percent isKindOfClass:[NSNumber class]]) percent = @(0);
    if (![current isKindOfClass:[NSNumber class]]) current = @(0);
    if (![total isKindOfClass:[NSNumber class]]) total = @(0);
    NSDictionary * userInfo = @{
                                IRPlayerPlayablePercentKey : percent,
                                IRPlayerPlayableCurrentKey : current,
                                IRPlayerPlayableTotalKey : total,
                                };
    [self postNotificationName:IRPlayerPlayableChangeNotificationName object:player userInfo:userInfo];
}

+ (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:object userInfo:userInfo];
    });
}

@end
