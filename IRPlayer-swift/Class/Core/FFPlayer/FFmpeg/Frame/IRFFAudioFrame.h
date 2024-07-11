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

@property (nonatomic, assign) float * samples;
@property (nonatomic, assign) NSInteger length;
@property (nonatomic, assign) NSInteger output_offset;

- (void)setSamplesLength:(NSUInteger)samplesLength;

@end

NS_ASSUME_NONNULL_END
