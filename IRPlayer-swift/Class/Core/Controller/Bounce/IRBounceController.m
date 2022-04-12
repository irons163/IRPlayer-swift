//
//  BonceController.m
//  IRPlayer
//
//  Created by Phil on 2019/8/19.
//  Copyright © 2019 Phil. All rights reserved.
//

#import "IRBounceController.h"
#import "IRGLView.h"

@interface IRBounceController ()

@property (nonatomic, weak) UIView *targetView;

@end

@implementation IRBounceController {
    CAShapeLayer *horizontalLineLayer, *verticalLineLayer;
    
}

- (void)addBounceToView:(UIView *)view {
    self.targetView = view;
    [self createLine];
}

- (void)removeBounceToView:(UIView *)view {
    if(horizontalLineLayer)
        [self.targetView.layer addSublayer:horizontalLineLayer];
    if(verticalLineLayer)
        [self.targetView.layer addSublayer:verticalLineLayer];
}

- (void)createLine {
    horizontalLineLayer = [CAShapeLayer layer];
    horizontalLineLayer.strokeColor = [[UIColor colorWithWhite:0.333f alpha:0.5f] CGColor];
    horizontalLineLayer.lineWidth = 0.0;
    horizontalLineLayer.fillColor = [[UIColor colorWithWhite:0.333f alpha:0.5f] CGColor];
    [self.targetView.layer addSublayer:horizontalLineLayer];
    
    verticalLineLayer = [CAShapeLayer layer];
    verticalLineLayer.strokeColor = [[UIColor colorWithWhite:0.333f alpha:0.5f] CGColor];
    verticalLineLayer.lineWidth = 0.0;
    verticalLineLayer.fillColor = [[UIColor colorWithWhite:0.333f alpha:0.5f] CGColor];
    
    [self.targetView.layer addSublayer:verticalLineLayer];
}

- (void)removeAndAddAnimateWithScrollValue:(CGFloat)scrollValue byScrollDirection:(IRScrollDirectionType)type {
    NSString* key = nil;
    CAShapeLayer* lineLayer = nil;
    UIBezierPath* startPath = nil;
    UIBezierPath* endPath = nil;
    
    startPath = [self getLinePathWithAmount:scrollValue byScrollDirection:type];
    endPath = [self getLinePathWithAmount:0.0 byScrollDirection:type];
    
    switch (type) {
        case Left:{
            key = @"bounce_right";
            lineLayer = horizontalLineLayer;
            break;
        }
        case Right:{
            key = @"bounce_left";
            lineLayer = horizontalLineLayer;
            break;
        }
        case Up:{
            key = @"bounce_bottom";
            lineLayer = verticalLineLayer;
            break;
        }
        case Down:{
            key = @"bounce_top";
            lineLayer = verticalLineLayer;
            break;
        }
        default:
            return;
    }
    
    [lineLayer removeAnimationForKey:key];
    lineLayer.path = [startPath CGPath];
    
    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
    morph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    morph.fromValue = (id) lineLayer.path;
    morph.toValue = (id) [endPath CGPath];
    morph.duration = 0.2;
    morph.removedOnCompletion = NO;
    morph.fillMode = kCAFillModeForwards;
    //    morph.delegate = self;
    [lineLayer addAnimation:morph forKey:key];
}

- (UIBezierPath*) getLinePathWithAmount:(CGFloat)amount byScrollDirection:(IRScrollDirectionType)type{
    CGPoint startPoint = CGPointZero;
    CGPoint midControlPoint = CGPointZero;
    CGPoint endPoint = CGPointZero;
    CGFloat bounceWidth = MIN(self.targetView.bounds.size.width/10, self.targetView.bounds.size.height/10);
    
    switch (type) {
        case Left:{
            startPoint = CGPointMake(self.targetView.bounds.size.width , 0);
            midControlPoint = CGPointMake(MAX(self.targetView.bounds.size.width + amount, self.targetView.bounds.size.width - bounceWidth), self.targetView.bounds.size.height/2);
            endPoint = CGPointMake(self.targetView.bounds.size.width , self.targetView.bounds.size.height);
            break;
        }
        case Right:{
            
            startPoint = CGPointZero;
            midControlPoint = CGPointMake(MIN(amount, bounceWidth), self.targetView.bounds.size.height/2);
            endPoint = CGPointMake(0, self.targetView.bounds.size.height);
            break;
        }
        case Up:{
            startPoint = CGPointMake(0 , self.targetView.bounds.size.height);
            midControlPoint = CGPointMake(self.targetView.bounds.size.width/2, MAX(self.targetView.bounds.size.height + amount, self.targetView.bounds.size.height - bounceWidth));
            endPoint = CGPointMake(self.targetView.bounds.size.width, self.targetView.bounds.size.height);
            break;
        }
        case Down:{
            startPoint = CGPointZero;
            midControlPoint = CGPointMake(self.targetView.bounds.size.width/2, MIN(amount, bounceWidth));
            endPoint = CGPointMake(self.targetView.bounds.size.width, 0);
            break;
        }
        default:
            return nil;
    }
    
    UIBezierPath *verticalLine = [UIBezierPath bezierPath];
    [verticalLine moveToPoint:startPoint];
    [verticalLine addQuadCurveToPoint:endPoint controlPoint:midControlPoint];
    [verticalLine closePath];
    
    return verticalLine;
}

-(UIBezierPath*) getRightLinePathWithAmount:(CGFloat)amount{
    UIBezierPath *verticalLine = [UIBezierPath bezierPath];
    CGPoint topPoint = CGPointMake(self.targetView.bounds.size.width , 0);
    CGPoint midControlPoint = CGPointMake(self.targetView.bounds.size.width - amount, self.targetView.bounds.size.height/2);
    CGPoint bottomPoint = CGPointMake(self.targetView.bounds.size.width , self.targetView.bounds.size.height);
    
    [verticalLine moveToPoint:topPoint];
    [verticalLine addQuadCurveToPoint:bottomPoint controlPoint:midControlPoint];
    [verticalLine closePath];
    
    return verticalLine;
}

@end
