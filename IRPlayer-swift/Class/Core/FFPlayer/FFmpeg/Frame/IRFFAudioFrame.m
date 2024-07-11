//
//  IRFFAudioFrame.m
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFAudioFrame.h"

@implementation IRFFAudioFrame
{
    size_t buffer_size;
}

- (IRFFFrameType)type
{
    return IRFFFrameTypeAudio;
}

- (int)size
{
    return (int)self->_length;
}

- (void)setSamplesLength:(NSUInteger)samplesLength
{
    if (self->buffer_size < samplesLength) {
        if (self->buffer_size > 0 && self->_samples != NULL) {
            free(self->_samples);
        }
        self->buffer_size = samplesLength;
        self->_samples = malloc(self->buffer_size);
    }
    self->_length = (int)samplesLength;
    self->_output_offset = 0;
}

- (void)dealloc
{
    if (self->buffer_size > 0 && self->_samples != NULL) {
        free(self->_samples);
    }
}

@end
