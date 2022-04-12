//
//  IRGestureController.m
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGestureController.h"
#import "IRGestureController+Private.h"

@interface IRGestureController ()

@property (nonatomic, strong) UITapGestureRecognizer *singleTapGR;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGR;
@property (nonatomic, strong) UIPanGestureRecognizer *panGR;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGR;
@property (nonatomic) IRPanDirection panDirection;
@property (nonatomic) IRPanLocation panLocation;
@property (nonatomic) IRPanMovingDirection panMovingDirection;

@end

@implementation IRGestureController

- (void)addGestureToView:(UIView *)view {
    _targetView = view;
    _targetView.multipleTouchEnabled = YES;
    [self.singleTapGR requireGestureRecognizerToFail:self.doubleTapGR];
    [self.singleTapGR  requireGestureRecognizerToFail:self.panGR];
    [self.targetView addGestureRecognizer:self.singleTapGR];
    [self.targetView addGestureRecognizer:self.doubleTapGR];
    [self.targetView addGestureRecognizer:self.panGR];
    [self.targetView addGestureRecognizer:self.pinchGR];
}

- (void)removeGestureToView:(UIView *)view {
    [view removeGestureRecognizer:self.singleTapGR];
    [view removeGestureRecognizer:self.doubleTapGR];
    [view removeGestureRecognizer:self.panGR];
    [view removeGestureRecognizer:self.pinchGR];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.panGR) {
        CGPoint translation = [(UIPanGestureRecognizer *)gestureRecognizer translationInView:self.targetView];
        CGFloat x = fabs(translation.x);
        CGFloat y = fabs(translation.y);
        if (x < y && self.disablePanMovingDirection & IRDisablePanMovingDirectionVertical) { /// up and down moving direction.
            return NO;
        } else if (x > y && self.disablePanMovingDirection & IRDisablePanMovingDirectionHorizontal) { /// left and right moving direction.
            return NO;
        }
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    IRGestureType type = IRGestureTypeUnknown;
    if (gestureRecognizer == self.singleTapGR) type = IRGestureTypeSingleTap;
    else if (gestureRecognizer == self.doubleTapGR) type = IRGestureTypeDoubleTap;
    else if (gestureRecognizer == self.panGR) type = IRGestureTypePan;
    else if (gestureRecognizer == self.pinchGR) type = IRGestureTypePinch;
    CGPoint locationPoint = [touch locationInView:touch.view];
    if (locationPoint.x > _targetView.bounds.size.width / 2) {
        self.panLocation = IRPanLocationRight;
    } else {
        self.panLocation = IRPanLocationLeft;
    }
    
    switch (type) {
        case IRGestureTypeUnknown: break;
        case IRGestureTypePan: {
            if (self.disableTypes & IRDisableGestureTypesPan) {
                return NO;
            }
        }
            break;
        case IRGestureTypePinch: {
            if (self.disableTypes & IRDisableGestureTypesPinch) {
                return NO;
            }
        }
            break;
        case IRGestureTypeDoubleTap: {
            if (self.disableTypes & IRDisableGestureTypesDoubleTap) {
                return NO;
            }
        }
            break;
        case IRGestureTypeSingleTap: {
            if (self.disableTypes & IRDisableGestureTypesSingleTap) {
                return NO;
            }
        }
            break;
    }
    
    if (self.triggerCondition) return self.triggerCondition(self, type, gestureRecognizer, touch);
    return YES;
}

// Whether to support multi-trigger, return YES, you can trigger a method with multiple gestures, return NO is mutually exclusive
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (otherGestureRecognizer != self.singleTapGR &&
        otherGestureRecognizer != self.doubleTapGR &&
        otherGestureRecognizer != self.panGR &&
        otherGestureRecognizer != self.pinchGR) return NO;
    
    if (gestureRecognizer == self.panGR) {
        CGPoint translation = [(UIPanGestureRecognizer *)gestureRecognizer translationInView:self.targetView];
        CGFloat x = fabs(translation.x);
        CGFloat y = fabs(translation.y);
        if (x < y && self.disablePanMovingDirection & IRDisablePanMovingDirectionVertical) {
            return YES;
        } else if (x > y && self.disablePanMovingDirection & IRDisablePanMovingDirectionHorizontal) {
            return YES;
        }
    }
    if (gestureRecognizer.numberOfTouches >= 2) {
        return NO;
    }
    return YES;
}

- (UITapGestureRecognizer *)singleTapGR {
    if (!_singleTapGR){
        _singleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
        _singleTapGR.delegate = self;
        _singleTapGR.delaysTouchesBegan = YES;
        _singleTapGR.delaysTouchesEnded = YES;
        _singleTapGR.numberOfTouchesRequired = 1;
        _singleTapGR.numberOfTapsRequired = 1;
    }
    return _singleTapGR;
}

- (UITapGestureRecognizer *)doubleTapGR {
    if (!_doubleTapGR) {
        _doubleTapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        _doubleTapGR.delegate = self;
        _doubleTapGR.delaysTouchesBegan = YES;
        _singleTapGR.delaysTouchesEnded = YES;
        _doubleTapGR.numberOfTouchesRequired = 1;
        _doubleTapGR.numberOfTapsRequired = 2;
    }
    return _doubleTapGR;
}

- (UIPanGestureRecognizer *)panGR {
    if (!_panGR) {
        _panGR = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panGR.delegate = self;
        _panGR.delaysTouchesBegan = YES;
        _panGR.delaysTouchesEnded = YES;
        _panGR.maximumNumberOfTouches = 1;
        _panGR.cancelsTouchesInView = YES;
    }
    return _panGR;
}

- (UIPinchGestureRecognizer *)pinchGR {
    if (!_pinchGR) {
        _pinchGR = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        _pinchGR.delegate = self;
        _pinchGR.delaysTouchesBegan = YES;
    }
    return _pinchGR;
}

- (void)handleSingleTap:(UITapGestureRecognizer *)tap {
    if (self.singleTapped) self.singleTapped(self);
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    if (self.doubleTapped) self.doubleTapped(self);
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translate = [pan translationInView:pan.view];
    CGPoint velocity = [pan velocityInView:pan.view];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.panMovingDirection = IRPanMovingDirectionUnkown;
            CGFloat x = fabs(velocity.x);
            CGFloat y = fabs(velocity.y);
            if (x > y) {
                self.panDirection = IRPanDirectionH;
            } else if (x < y) {
                self.panDirection = IRPanDirectionV;
            } else {
                self.panDirection = IRPanDirectionUnknown;
            }
            
            if (self.beganPan) self.beganPan(self, self.panDirection, self.panLocation);
        }
            break;
        case UIGestureRecognizerStateChanged: {
            switch (_panDirection) {
                case IRPanDirectionH: {
                    if (translate.x > 0) {
                        self.panMovingDirection = IRPanMovingDirectionRight;
                    } else if (translate.y < 0) {
                        self.panMovingDirection = IRPanMovingDirectionLeft;
                    }
                }
                    break;
                case IRPanDirectionV: {
                    if (translate.y > 0) {
                        self.panMovingDirection = IRPanMovingDirectionBottom;
                    } else {
                        self.panMovingDirection = IRPanMovingDirectionTop;
                    }
                }
                    break;
                case IRPanDirectionUnknown:
                    break;
            }
            if (self.changedPan) self.changedPan(self, self.panDirection, self.panLocation, velocity);
        }
            break;
        case UIGestureRecognizerStateFailed:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            if (self.endedPan) self.endedPan(self, self.panDirection, self.panLocation);
        }
            break;
        default:
            break;
    }
//    [pan setTranslation:CGPointZero inView:pan.view];
}

- (void)handlePinch:(UIPinchGestureRecognizer *)pinch {
    switch (pinch.state) {
        case UIGestureRecognizerStateEnded: {
            if (self.pinched) self.pinched(self, pinch.scale);
        }
            break;
        default:
            break;
    }
}

@end
