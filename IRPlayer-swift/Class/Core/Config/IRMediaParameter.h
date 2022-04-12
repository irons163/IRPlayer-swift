//
//  IRMediaParameter.h
//  IRPlayer
//
//  Created by Phil on 2019/7/5.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRMediaParameter : NSObject

@property float width;
@property float height;
@property BOOL autoUpdate; // default = YES

- (instancetype)initWithWidth:(float)width height:(float)height;

@end

NS_ASSUME_NONNULL_END
