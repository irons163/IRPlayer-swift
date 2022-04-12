//
//  IRFFFrame.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFFrame.h"
#import "IRFFTools.h"

@implementation IRFFFrame

- (void)startPlaying
{
    self->_playing = YES;
    if ([self.delegate respondsToSelector:@selector(frameDidStartPlaying:)]) {
        [self.delegate frameDidStartPlaying:self];
    }
}

- (void)stopPlaying
{
    self->_playing = NO;
    if ([self.delegate respondsToSelector:@selector(frameDidStopPlaying:)]) {
        [self.delegate frameDidStopPlaying:self];
    }
}

- (void)cancel
{
    self->_playing = NO;
    if ([self.delegate respondsToSelector:@selector(frameDidCancel:)]) {
        [self.delegate frameDidCancel:self];
    }
}

@end


@implementation IRFFSubtileFrame

- (IRFFFrameType)type
{
    return IRFFFrameTypeSubtitle;
}

@end


@implementation IRFFArtworkFrame

- (IRFFFrameType)type
{
    return IRFFFrameTypeArtwork;
}

@end
