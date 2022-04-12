//
//  IRGLGestureControl.h
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IRGestureController.h"
#import "IRGLView.h"
#import "IRSmoothScrollController.h"

NS_ASSUME_NONNULL_BEGIN

@interface IRGLGestureController : IRGestureController

@property (weak) id<IRGLViewDelegate> delegate;
@property BOOL doubleTapEnable;
@property BOOL swipeEnable;
@property (nonatomic, nullable) IRGLRenderMode *currentMode;
@property (nonatomic, weak) IRSmoothScrollController *smoothScroll;

@property (nonatomic, weak, readonly) IRGLView *targetView;

@end

NS_ASSUME_NONNULL_END
