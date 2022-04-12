//
//  IRSmoothScroll.h
//  IRPlayer
//
//  Created by Phil on 2019/9/2.
//  Copyright © 2019 Phil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IRGLView.h"
#import "IRGLProgram2D.h"

NS_ASSUME_NONNULL_BEGIN

@protocol IRGLViewDelegate

@optional
- (void)glViewWillBeginDragging:(IRGLView *)glView;
- (void)glViewDidEndDragging:(IRGLView *)glView willDecelerate:(BOOL)decelerate;
- (void)glViewDidEndDecelerating:(IRGLView *)glView;
- (void)glViewDidScrollToBounds:(IRGLView *)glView;
- (void)glViewWillBeginZooming:(IRGLView *)glView;
- (void)glViewDidEndZooming:(IRGLView *)glView atScale:(CGFloat)scale;
@end

@interface IRSmoothScrollController : NSObject<IRGLProgramDelegate>

@property (weak) id<IRGLViewDelegate> delegate;
@property (nonatomic) IRGLRenderMode *currentMode;
@property (nonatomic, weak, readonly) IRGLView *targetView;
@property (nonatomic) BOOL isPaned;

- (instancetype)initWithTargetView:(IRGLView *)targetView;

- (void)resetSmoothScroll;
- (void)calculateSmoothScroll:(CGPoint)velocity;

- (void)scrollByDx:(float)dx dy:(float)dy;
- (void)shiftDegreeX:(float)degreeX degreeY:(float)degreeY;

@end

NS_ASSUME_NONNULL_END
