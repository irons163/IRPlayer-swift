//
//  IRSmoothScroll.m
//  IRPlayer
//
//  Created by Phil on 2019/9/2.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRSmoothScrollController.h"
#import "IRBounceController.h"
#import "IRGLTransformController.h"
#import "IRGLRenderMode.h"

@interface IRSmoothScrollController()

@end

@implementation IRSmoothScrollController {
    //Smooth Scroll
    CGPoint finalPoint;
    CGPoint alreadyPoint;
    CGFloat slideDuration;
    CADisplayLink *timer;
    NSTimeInterval startTimestamp;
    NSTimeInterval lastTimestamp;
    BOOL didHorizontalBoundsBonce, didVerticalBoundsBonce;
    IRBounceController *bounce;
}

- (instancetype)initWithTargetView:(IRGLView *)targetView {
    if (self = [super init]) {
        _targetView = targetView;
        bounce = [[IRBounceController alloc] init];
        [bounce addBounceToView:self.targetView];
        
        timer = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [timer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return self;
}

- (void)tick:(CADisplayLink *)sender {
    if (CGPointEqualToPoint(finalPoint, CGPointZero)) {
        return;
    }
    
    if(startTimestamp == 0) {
        startTimestamp = sender.timestamp;
    }
    
    CGFloat duration = MIN(slideDuration, sender.timestamp - startTimestamp);
    //    CGFloat persentage = pow(duration / slideDuration, 1);
    CGFloat persentage = duration / slideDuration;
    persentage = -1 * persentage*(persentage-2); // quadratic easing out
    /* //cubic easing out
     persentage -= 1;
     persentage = persentage*persentage*persentage + 1;
     */
    CGFloat moveX = finalPoint.x * persentage - alreadyPoint.x;
    CGFloat moveY = finalPoint.y * persentage - alreadyPoint.y;
    
    alreadyPoint.x += moveX;
    alreadyPoint.y += moveY;
    
    if(self.isPaned)
        [self.targetView scrollByDx:moveX*[[UIScreen mainScreen] scale] dy:-1*moveY*[[UIScreen mainScreen] scale]];
    else{
        [_currentMode.shiftController shiftDegreeX:moveX degreeY:-1*moveY];
        [self.targetView render:nil];
    }
    
    if(CGPointEqualToPoint(finalPoint, alreadyPoint)){
        [self resetSmoothScroll];
        if(self.delegate)
            [self.delegate glViewDidEndDecelerating:self.targetView];
    }
}

- (void)resetSmoothScroll {
    finalPoint = CGPointZero;
    alreadyPoint = CGPointZero;
    startTimestamp = 0;
    didHorizontalBoundsBonce = NO;
    didVerticalBoundsBonce = NO;
}

- (void)calculateSmoothScroll:(CGPoint)velocity {
    CGFloat magnitude = sqrtf((velocity.x * velocity.x) + (velocity.y * velocity.y));
    CGFloat slideMult = magnitude / 200;
    NSLog(@"magnitude: %f, slideMult: %f", magnitude, slideMult);
    
    [self resetSmoothScroll];
    float slideFactor = 0.05 * slideMult; // Increase for more of a slide
    finalPoint = CGPointMake(0 + (velocity.x * slideFactor),
                             0 + (velocity.y * slideFactor));
    slideDuration = slideFactor*2;
}

- (void)scrollByDx:(float)dx dy:(float)dy {
    [self.targetView scrollByDx:dx dy:dy];
}

- (void)shiftDegreeX:(float)degreeX degreeY:(float)degreeY {
    CGFloat unmoveYetX = finalPoint.x - alreadyPoint.x;
    CGFloat unmoveYetY = finalPoint.y - alreadyPoint.y;
    degreeX += unmoveYetX;
    degreeY += -1*unmoveYetY;
    
    [self resetSmoothScroll];
    self.isPaned = NO;
    
    finalPoint = CGPointMake(degreeX,
                             -1*degreeY);
    slideDuration = 0.5;
}

- (void)didScrollToBounds:(IRGLTransformControllerScrollToBounds)bounds withProgram:(IRGLProgram2D *)program {
    CGFloat moveX = finalPoint.x - alreadyPoint.x;
    CGFloat moveY = finalPoint.y - alreadyPoint.y;
    
    IRScrollDirectionType scrollDirectionType = None;
    
    switch (bounds) {
        case IRGLTransformControllerScrollToHorizontalBounds:
            moveY = 0;
            break;
        case IRGLTransformControllerScrollToVerticalBounds:
            moveX = 0;
            break;
        case IRGLTransformControllerScrollToHorizontalandVerticalBounds:
            
            break;
            
        default:
            moveX = 0;
            moveY = 0;
            break;
    }
    
    if(moveX > 0)
        scrollDirectionType = Right;
    else if(moveX < 0)
        scrollDirectionType = Left;
    
    if(!didHorizontalBoundsBonce && (scrollDirectionType == Left || scrollDirectionType == Right)){
        [bounce removeAndAddAnimateWithScrollValue:moveX byScrollDirection:scrollDirectionType];
        didHorizontalBoundsBonce = YES;
    }
    
    if(moveY > 0)
        scrollDirectionType = Down;
    else if(moveY < 0)
        scrollDirectionType = Up;
    
    if(!didVerticalBoundsBonce && (scrollDirectionType == Up || scrollDirectionType == Down)){
        [bounce removeAndAddAnimateWithScrollValue:moveY byScrollDirection:scrollDirectionType];
        didVerticalBoundsBonce = YES;
    }
    
    if(self.delegate)
        [self.delegate glViewDidScrollToBounds:self.targetView];
}

@end
