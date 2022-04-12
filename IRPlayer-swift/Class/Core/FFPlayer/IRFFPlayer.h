//
//  IRFFPlayer.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
//#import "IRPlayerImp.h"
//#import "IRPlayerImp-Swift.h"
@class IRPlayerImp;
@class IRPlayerTrack;
//typedef NS_ENUM(NSInteger, IRPlayerState);

NS_ASSUME_NONNULL_BEGIN

@interface IRFFPlayer : NSObject

+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)init NS_UNAVAILABLE;

+ (instancetype)playerWithAbstractPlayer:(IRPlayerImp *)abstractPlayer;

@property (nonatomic, weak, readonly) IRPlayerImp * abstractPlayer;

@property (nonatomic, assign, readonly) IRPlayerState state;
@property (nonatomic, assign, readonly) CGSize presentationSize;
@property (nonatomic, assign, readonly) NSTimeInterval bitrate;
@property (nonatomic, assign, readonly) NSTimeInterval progress;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval playableTime;
@property (nonatomic, assign, readonly) BOOL seeking;

- (void)replaceVideo;
- (void)reloadVolume;
- (void)reloadPlayableBufferInterval;

- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completeHandler:(nullable void(^)(BOOL finished))completeHandler;


#pragma mark - track info

@property (nonatomic, assign, readonly) BOOL videoEnable;
@property (nonatomic, assign, readonly) BOOL audioEnable;

@property (nonatomic, strong, readonly) IRPlayerTrack * videoTrack;
@property (nonatomic, strong, readonly) IRPlayerTrack * audioTrack;

@property (nonatomic, strong, readonly) NSArray <IRPlayerTrack *> * videoTracks;
@property (nonatomic, strong, readonly) NSArray <IRPlayerTrack *> * audioTracks;

- (void)selectAudioTrackIndex:(int)audioTrackIndex;

@end

NS_ASSUME_NONNULL_END
