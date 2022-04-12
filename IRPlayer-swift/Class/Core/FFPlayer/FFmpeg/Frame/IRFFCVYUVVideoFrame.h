//
//  IRFFCVYUVVideoFrame.h
//  IRPlayer
//
//  Created by Phil on 2019/10/25.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IRFFVideoFrame.h"

NS_ASSUME_NONNULL_BEGIN

// CoreVideo YUV frame
@interface IRFFCVYUVVideoFrame : IRFFVideoFrame

@property (nonatomic, assign, readonly) CVPixelBufferRef pixelBuffer;

- (instancetype)initWithAVPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
