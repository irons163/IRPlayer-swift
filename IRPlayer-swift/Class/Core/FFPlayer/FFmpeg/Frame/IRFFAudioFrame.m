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
    return (int)self->length;
}

- (void)setSamplesLength:(NSUInteger)samplesLength
{
    if (self->buffer_size < samplesLength) {
        if (self->buffer_size > 0 && self->samples != NULL) {
            free(self->samples);
        }
        self->buffer_size = samplesLength;
        self->samples = malloc(self->buffer_size);
    }
    self->length = (int)samplesLength;
    self->output_offset = 0;
}

- (void)dealloc
{
    if (self->buffer_size > 0 && self->samples != NULL) {
        free(self->samples);
    }
}

@end
