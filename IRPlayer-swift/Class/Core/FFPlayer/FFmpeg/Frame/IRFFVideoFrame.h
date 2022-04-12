//
//  IRFFVideoFrame.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFFrame.h"
#import "IRPLFImage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int, IRYUVChannel) {
    IRYUVChannelLuma = 0,
    IRYUVChannelChromaB = 1,
    IRYUVChannelChromaR = 2,
    IRYUVChannelCount = 3,
};

@interface IRFFVideoFrame : IRFFFrame

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

@end






NS_ASSUME_NONNULL_END
