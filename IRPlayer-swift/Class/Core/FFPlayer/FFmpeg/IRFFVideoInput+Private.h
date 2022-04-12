//
//  IRFFVideoInput+Private.h
//  IRPlayer
//
//  Created by Phil on 2019/10/24.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRFFVideoInput.h"
#import "IRFFDecoder.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRFFVideoInput ()

@property (nonatomic, strong) id<IRFFDecoderVideoOutput> videoOutput;

@end

NS_ASSUME_NONNULL_END
