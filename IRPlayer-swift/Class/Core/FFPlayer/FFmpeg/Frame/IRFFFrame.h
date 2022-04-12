//
//  IRFFFrame.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IRFFFrameType) {
    IRFFFrameTypeVideo,
    IRFFFrameTypeAVYUVVideo,
    IRFFFrameTypeCVYUVVideo,
    IRFFFrameTypeAudio,
    IRFFFrameTypeSubtitle,
    IRFFFrameTypeArtwork,
};

@class IRFFFrame;

@protocol IRFFFrameDelegate <NSObject>

- (void)frameDidStartPlaying:(IRFFFrame *)frame;
- (void)frameDidStopPlaying:(IRFFFrame *)frame;
- (void)frameDidCancel:(IRFFFrame *)frame;

@end

@interface IRFFFrame : NSObject

@property (nonatomic, weak) id <IRFFFrameDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL playing;

@property (nonatomic, assign) IRFFFrameType type;
@property (nonatomic, assign) NSTimeInterval position;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign, readonly) int size;

- (void)startPlaying;
- (void)stopPlaying;
- (void)cancel;

@end


@interface IRFFSubtileFrame : IRFFFrame

@end


@interface IRFFArtworkFrame : IRFFFrame

@property (nonatomic, strong) NSData * picture;

@end

NS_ASSUME_NONNULL_END
