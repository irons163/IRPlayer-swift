//
//  IRGLGestureControl.m
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRGLGestureController.h"
#import "IRGestureController+Private.h"
#import "IRGLView.h"
#import "IRGLRenderMode.h"

//typedef NS_ENUM(NSInteger, IRScrollDirectionType){
//    None, //default
//    Left,
//    Right,
//    Up,
//    Down
//};

@interface IRGLGestureController ()<IRGLRenderModeDelegate, UIGestureRecognizerDelegate>

//@property (nonatomic, strong) UITapGestureRecognizer *singleTapGR;
//@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGR;
//@property (nonatomic, strong) UIPanGestureRecognizer *panGR;
//@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGR;
@property (nonatomic, strong) UIRotationGestureRecognizer *rotateGR;
//@property (nonatomic) IRPanDirection panDirection;
//@property (nonatomic) IRPanLocation panLocation;
//@property (nonatomic) IRPanMovingDirection panMovingDirection;
//@property (nonatomic, weak) IRGLView *targetView;

@end

@implementation IRGLGestureController {
    BOOL isTouchedInProgram;
}
@dynamic targetView;

- (void)addGestureToView:(IRGLView *)view {
    [super addGestureToView:view];
    
    [self initDefaultValue];
}

- (void)removeGestureToView:(UIView *)view {
    [super removeGestureToView:view];
}

- (void)initDefaultValue {
    self.swipeEnable = YES;
    
    _rotateGR = [[UIRotationGestureRecognizer alloc] initWithTarget:self
                                                                                         action:@selector(handleRotate:)];
    [self.targetView addGestureRecognizer:self.rotateGR];
    
    isTouchedInProgram = NO;
    self.doubleTapEnable = YES;
}

- (void)setCurrentMode:(IRGLRenderMode *)currentMode {
    _currentMode = currentMode;
    if(_currentMode.program)
        _currentMode.program.delegate = self.smoothScroll;
    _currentMode.delegate = self;
    self.smoothScroll.currentMode = self.currentMode;
}

#pragma mark - Gesture Callback

- (void)handlePan:(UIPanGestureRecognizer*)gr {
    [super handlePan:gr];
    
    NSLog(@"didPan, state %zd",gr.state);
    
    self.smoothScroll.isPaned = YES;
    [self.smoothScroll resetSmoothScroll];
    
    if ((UIGestureRecognizerStateCancelled == gr.state ||
         UIGestureRecognizerStateFailed == gr.state))
    {
        isTouchedInProgram = NO;
        
        if(self.delegate)
            [self.delegate glViewDidEndDragging:self.targetView willDecelerate:NO];
    }
    else if(UIGestureRecognizerStateEnded == gr.state){
        isTouchedInProgram = NO;
        
        CGPoint velocity = [gr velocityInView:self.targetView];
        [self.smoothScroll calculateSmoothScroll:velocity];
        
        if(self.delegate)
            [self.delegate glViewDidEndDragging:self.targetView willDecelerate:CGPointEqualToPoint(velocity, CGPointZero)];
    }
    else if(UIGestureRecognizerStateBegan == gr.state){
        CGPoint touchedPoint = [gr locationInView:self.targetView];
        touchedPoint.x *= [UIScreen mainScreen].scale;
        touchedPoint.y = self.targetView.frame.size.height - touchedPoint.y;
        touchedPoint.y *= [UIScreen mainScreen].scale;
        isTouchedInProgram = [_currentMode.program touchedInProgram:touchedPoint];
    }else{
        if(!isTouchedInProgram)
            return;
        
        if(self.delegate)
            [self.delegate glViewWillBeginDragging:self.targetView];
        
        CGPoint screenOffset = [(UIPanGestureRecognizer*)gr translationInView:self.targetView];
        
        [self.smoothScroll scrollByDx:screenOffset.x*[[UIScreen mainScreen] scale] dy:-1*screenOffset.y*[[UIScreen mainScreen] scale]];
        
        [(UIPanGestureRecognizer*)gr setTranslation:CGPointZero inView:self.targetView];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer*)sender {
    [super handlePinch:sender];
    
    NSLog(@"didPinch %f state %zd",sender.scale,sender.state);
    
    if ((UIGestureRecognizerStateCancelled == sender.state ||
         UIGestureRecognizerStateEnded == sender.state ||
         UIGestureRecognizerStateFailed == sender.state))
    {
        isTouchedInProgram = NO;
    }else if(UIGestureRecognizerStateBegan == sender.state){
        CGPoint touchedPoint = [sender locationInView:self.targetView];
        touchedPoint.x *= [UIScreen mainScreen].scale;
        touchedPoint.y = self.targetView.frame.size.height - touchedPoint.y;
        touchedPoint.y *= [UIScreen mainScreen].scale;
        isTouchedInProgram = [_currentMode.program touchedInProgram:touchedPoint];
    }else{
        if(!isTouchedInProgram)
            return;
        if(sender.numberOfTouches < 2)
            return;
        
        CGPoint p1 = [sender locationOfTouch:0 inView:self.targetView];
        CGPoint p2 = [sender locationOfTouch:1 inView:self.targetView];
        
        if(self.delegate)
            [self.delegate glViewWillBeginZooming:self.targetView];
        [(IRGLView*)self.targetView updateScopeByFx:(p1.x + p2.x) / 2 fy:(p1.y + p2.y) / 2 dsx:sender.scale dsy:sender.scale];
        if(self.delegate)
            [self.delegate glViewDidEndZooming:self.targetView atScale:0];
        
        sender.scale = 1;
    }
}

- (void)handleRotate:(UIRotationGestureRecognizer*)gr {
    NSLog(@"didRotate, state %zd",gr.state);
    if ((UIGestureRecognizerStateCancelled == gr.state ||
         UIGestureRecognizerStateEnded == gr.state ||
         UIGestureRecognizerStateFailed == gr.state))
    {
        isTouchedInProgram = NO;
    }
    else if(UIGestureRecognizerStateBegan == gr.state){
        CGPoint touchedPoint = [gr locationInView:self.targetView];
        touchedPoint.x *= [UIScreen mainScreen].scale;
        touchedPoint.y = self.targetView.frame.size.height - touchedPoint.y;
        touchedPoint.y *= [UIScreen mainScreen].scale;
        isTouchedInProgram = [_currentMode.program touchedInProgram:touchedPoint];
    }else{
        if(!isTouchedInProgram)
            return;
        
        if(self.delegate)
            [self.delegate glViewWillBeginDragging:self.targetView];
        
        NSLog(@"rotate:%f",gr.rotation);
        
        [self updateRotation:gr.rotation];
        
        gr.rotation = 0;
        
        if(self.delegate)
            [self.delegate glViewDidEndDragging:nil willDecelerate:NO];
        
        //    if(self.delegate)
        //        [self.delegate scrollViewDidEndDecelerating:nil];
    }
}

- (void)updateRotation:(float)rotateRadians {
    [_currentMode.program didRotate: -1 * rotateRadians];
    [(IRGLView*)self.targetView render:nil];
}

- (void)handleDoubleTap:(UITapGestureRecognizer*)gr {
    [super handleDoubleTap:gr];
    
    NSLog(@"didDoubleTap, state %zd",gr.state);
    
    isTouchedInProgram = NO;
    
    CGPoint touchedPoint = [gr locationInView:self.targetView];
    touchedPoint.x *= [UIScreen mainScreen].scale;
    touchedPoint.y = self.targetView.frame.size.height - touchedPoint.y;
    touchedPoint.y *= [UIScreen mainScreen].scale;
    isTouchedInProgram = [_currentMode.program touchedInProgram:touchedPoint];
    
    if(!isTouchedInProgram)
        return;
    
    _currentMode.program.doResetToDefaultScaleBlock = ^BOOL(IRGLProgram2D *program) {
        if(CGPointEqualToPoint([program getCurrentScale], CGPointMake(1.0,1.0)))
            return NO;

        [program setDefaultScale:1.0];

        return YES;
    };
    
    [_currentMode.program didDoubleTap];
    
    [_currentMode update]; //It for multi_4P, not a good method, should modify future.
    
    [(IRGLView*)self.targetView render:nil];
}

//Not consider Multi program status yet.
- (BOOL)isProgramZooming {
    return _currentMode.program && !CGPointEqualToPoint([_currentMode.program getCurrentScale], CGPointMake(1.0,1.0));
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    BOOL shouldBegain = [super gestureRecognizerShouldBegin:gestureRecognizer];
    
    if ((!self.doubleTapEnable || ![self isProgramZooming]) && gestureRecognizer == self.doubleTapGR){
        return NO;
    }else if([gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]] && [self isProgramZooming]){
        return NO;
    }
    return shouldBegain;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    BOOL shouldRecognizeSimultaneously = [super gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
    
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]  && [otherGestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]] && (self.swipeEnable && ![self isProgramZooming])) {
        return YES;
    } else {
        return shouldRecognizeSimultaneously;
    }
}

- (void)programDidCreate:(IRGLProgram2D *)program {
    program.delegate = self.smoothScroll;
}

@end
