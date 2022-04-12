//
//  IRGestureController+Private.h
//  IRPlayer
//
//  Created by Phil on 2019/9/2.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGestureController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGestureController (Private)

- (void)handleSingleTap:(UITapGestureRecognizer *)tap;
- (void)handleDoubleTap:(UITapGestureRecognizer *)tap;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)handlePinch:(UIPinchGestureRecognizer *)pinch;

@end

NS_ASSUME_NONNULL_END
