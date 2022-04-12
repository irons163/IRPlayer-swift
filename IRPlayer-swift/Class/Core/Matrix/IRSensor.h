//
//  IRSensor.h
//  IRPlayer
//
//  Created by Phil on 2019/8/14.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IRSmoothScrollController.h"

@class IRGLView;

NS_ASSUME_NONNULL_BEGIN

@interface IRSensor : NSObject

@property (nonatomic, weak) IRGLView *targetView;
@property (nonatomic, weak) IRSmoothScrollController *smoothScroll;

#pragma mark - Wide Functions
- (BOOL)resetUnit;
- (void)stopMotionDetection;

@end

NS_ASSUME_NONNULL_END
