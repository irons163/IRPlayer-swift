//
//  IRAudioManager.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRAudioManagerInterruptionType) {
    IRAudioManagerInterruptionTypeBegin,
    IRAudioManagerInterruptionTypeEnded,
};

typedef NS_ENUM(NSUInteger, IRAudioManagerInterruptionOption) {
    IRAudioManagerInterruptionOptionNone,
    IRAudioManagerInterruptionOptionShouldResume,
};

typedef NS_ENUM(NSUInteger, IRAudioManagerRouteChangeReason) {
    IRAudioManagerRouteChangeReasonOldDeviceUnavailable,
};

@class IRAudioManager;

@protocol IRAudioManagerDelegate <NSObject>
- (void)audioManager:(IRAudioManager *)audioManager outputData:(float *)outputData numberOfFrames:(UInt32)numberOfFrames numberOfChannels:(UInt32)numberOfChannels;
@end

typedef void (^IRAudioManagerInterruptionHandler)(id handlerTarget, IRAudioManager * audioManager, IRAudioManagerInterruptionType type, IRAudioManagerInterruptionOption option);
typedef void (^IRAudioManagerRouteChangeHandler)(id handlerTarget, IRAudioManager * audioManager, IRAudioManagerRouteChangeReason reason);

@interface IRAudioManager : NSObject

+ (instancetype)new NS_UNAVAILABLE;
//- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)manager;

@property (nonatomic, assign) float volume;

@property (nonatomic, weak, readonly) id <IRAudioManagerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL playing;

@property (nonatomic, assign, readonly) Float64 samplingRate;
@property (nonatomic, assign, readonly) UInt32 numberOfChannels;

- (void)setHandlerTarget:(id)handlerTarget
            interruption:(IRAudioManagerInterruptionHandler)interruptionHandler
             routeChange:(IRAudioManagerRouteChangeHandler)routeChangeHandler;
- (void)removeHandlerTarget:(id)handlerTarget;

- (void)playWithDelegate:(id <IRAudioManagerDelegate>)delegate;
- (void)pause;

- (BOOL)registerAudioSession;
- (void)unregisterAudioSession;

@end


NS_ASSUME_NONNULL_END
