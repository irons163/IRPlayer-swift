//
//  IRFFAudioFrame.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFFrame.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFAudioFrame : IRFFFrame
{
@public
    float * samples;
    int length;
    int output_offset;
}

- (void)setSamplesLength:(NSUInteger)samplesLength;

@end

NS_ASSUME_NONNULL_END
