//
//  IRFFCVYUVVideoFrame.m
//  IRPlayer
//
//  Created by Phil on 2019/10/25.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFCVYUVVideoFrame.h"

@implementation IRFFCVYUVVideoFrame {
    BOOL shouldRelease;
}

- (IRFFFrameType)type
{
    return IRFFFrameTypeCVYUVVideo;
}

- (instancetype)initWithAVPixelBuffer:(CVPixelBufferRef)pixelBuffer shouldRelease:(BOOL)shouldRelease
{
    if (self = [super init]) {
        self->_pixelBuffer = pixelBuffer;
        self->shouldRelease = shouldRelease;
    }
    return self;
}

- (int)width {
    const GLsizei frameWidth = (GLsizei)CVPixelBufferGetWidth(self->_pixelBuffer);
    return frameWidth;
}

- (int)height {
    const GLsizei frameHeight = (GLsizei)CVPixelBufferGetHeight(self->_pixelBuffer);
    return frameHeight;
}

- (void)dealloc
{
    if (self->_pixelBuffer) {
        if (shouldRelease) {
            CVPixelBufferRelease(self->_pixelBuffer);
        }
        self->_pixelBuffer = NULL;
    }
}

@end
